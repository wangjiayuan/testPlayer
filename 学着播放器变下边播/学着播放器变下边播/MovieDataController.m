//
//  MovieDataController.m
//  学着播放器变下边播
//
//  Created by apple on 16/2/26.
//  Copyright © 2016年 cheniue. All rights reserved.
//

#import "MovieDataController.h"
#import <MobileCoreServices/MobileCoreServices.h>

@implementation VideoFileInfo

@end

@implementation MovieDataController
#pragma mark 初始化对象
-(instancetype)initWithURL:(NSURL*)url
{
    self = [super init];
    if (self)
    {
        ///视频资源请求数组
        _resourceLoadingRequests = [[NSMutableArray alloc]initWithCapacity:0];
        ///唯一的视频下载线程
        _dataTask = nil;
        ///获取视频资源大小的线程
        _fileLengthTask = nil;
        ///视频资源的大小
        _fileLength = 0;
        ///是否已经获得文件的大小
        _haveGetFileLength = NO;
        ////多个下载获得的视频有效数据范围数组
        _visibleDataRangeInfo = [[NSMutableArray alloc]initWithCapacity:0];
        ////需要下载的文件范围
        _needDownLoadRange = NSMakeRange(0, 0);
        ////正在执行的下载范围
        _currentDownLoadRange = NSMakeRange(0, 0);
        ////正在下载资源已完成的大小
        _currentDownLoadLength = 0;
        ///唯一的资源下载会话
        _downLoadSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:[NSOperationQueue mainQueue]];
        ///下载资源的起始文件地址
        _videoFileURL = [url copy];
        ///文件管理对象
        _defaultFileManage = [NSFileManager defaultManager];
        ///当前操作的文件路径
        _currentWriteFilePath = nil;
        _currentFileInfo = nil;
        
        self.lengthTryCount = 0;
        self.fileTryCount = 0;
        self.playStartLocation = 0;
    }
    return self;
}
#pragma mark 操作函数
//合并两个文件的内容
-(NSString*)mergeFileFrontPart:(NSString*)pFilePath flowPart:(NSString*)fFilePath
{
    if (![_defaultFileManage fileExistsAtPath:pFilePath])
    {
        return nil;
    }
    if (![_defaultFileManage fileExistsAtPath:fFilePath])
    {
        return nil;
    }
    NSString *newFilePath = [self getRandomFilePath];
    [_defaultFileManage copyItemAtPath:pFilePath toPath:newFilePath error:nil];
    NSFileHandle *fFileHandle = [NSFileHandle fileHandleForReadingAtPath:fFilePath];
    NSFileHandle *wFileHandle = [NSFileHandle fileHandleForWritingAtPath:newFilePath];
    NSInteger currentOffset = 0;
    NSInteger totalFileSize = [fFileHandle seekToEndOfFile];
    while (currentOffset < totalFileSize)
    {
        [fFileHandle seekToFileOffset:currentOffset];
        if ((totalFileSize - currentOffset) >= 1024*1024)
        {
            NSData *data = [fFileHandle readDataOfLength:1024*1024];
            [wFileHandle seekToEndOfFile];
            [wFileHandle writeData:data];
        }
        else
        {
            NSData *data = [fFileHandle readDataOfLength:(totalFileSize - currentOffset)];
            [wFileHandle seekToEndOfFile];
            [wFileHandle writeData:data];
        }
        currentOffset += 1024*1024;
    }
    [fFileHandle synchronizeFile];
    [fFileHandle closeFile];
    [wFileHandle synchronizeFile];
    [wFileHandle closeFile];
    return newFilePath;
}
//获取资源文件保存的文件夹路径
-(NSString*)getVideoDirectoriePath
{
    NSString *directorieName = [NSString stringWithFormat:@"%@",@((NSUInteger)self)];
    NSString *document = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject;
    NSString *directoriePath = [document stringByAppendingPathComponent:directorieName];
    if (![_defaultFileManage fileExistsAtPath:directoriePath])
    {
        [_defaultFileManage createDirectoryAtPath:directoriePath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return directoriePath;
}
//获得一个文件路径
-(NSString*)getRandomFilePath
{
    NSString *directoriePath = [self getVideoDirectoriePath];
    NSDateFormatter *formatter = [[NSDateFormatter alloc]init];
    [formatter setDateFormat:@"yyyyMMddHHmmssSSS"];
    NSString *fileName = [NSString stringWithFormat:@"%@_%@",[formatter stringFromDate:[NSDate date]],@(arc4random()%1024)];
    NSString *filePath = [directoriePath stringByAppendingPathComponent:fileName];
    return filePath;
}
//获取视频资源文件大小
-(void)getVideoFileLength
{
    if (_haveGetFileLength)
    {
        return;
    }
    
    [_fileLengthTask cancel];
    _fileLengthTask = nil;
    
    NSURLComponents *actualURLComponents = [[NSURLComponents alloc] initWithURL:_videoFileURL resolvingAgainstBaseURL:NO];
    actualURLComponents.scheme = @"http";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[actualURLComponents URL]];
    [request setHTTPMethod:@"HEAD"];
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithRequest:request completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        //获取视频资源大小结束
        
        if (error == nil) //获取成功
        {
            _fileLength = [response expectedContentLength];
            _haveGetFileLength = YES;
            [self setupVideoRequestInfo];
            [self setDownLoadSettingInfo];
        }
        else
        {
            self.lengthTryCount++;
            if (self.lengthTryCount<ERROR_TRY_COUNT)
            {
                [self getVideoFileLength];
            }
        }
        
    }];
    [task resume];
}
//创建空白文件
-(void)createNewBlankVideoFile
{
    _currentWriteFilePath = [self getRandomFilePath];
    
    [_defaultFileManage createFileAtPath:_currentWriteFilePath contents:nil attributes:nil];
    if ([_defaultFileManage fileExistsAtPath:_currentWriteFilePath])
    {
        _fileWriteHandle = [NSFileHandle fileHandleForWritingAtPath:_currentWriteFilePath];
    }
}
//设置下载配置
-(void)setDownLoadSettingInfo
{
    _currentDownLoadLength = 0;
    if (self.playStartLocation < 0)
    {
        self.playStartLocation = 0;
    }
    if (self.playStartLocation >= (_fileLength -1))
    {
        return;
    }
    if (_fileLength <= 0)
    {
        return;
    }
    _needDownLoadRange = NSMakeRange(self.playStartLocation, _fileLength - self.playStartLocation - 1);
    _currentDownLoadRange = NSMakeRange(_needDownLoadRange.location, _needDownLoadRange.length);
    for (NSInteger i=0; i<_visibleDataRangeInfo.count; i++)
    {
        VideoFileInfo *info = [_visibleDataRangeInfo objectAtIndex:i];
        NSRange range = info.range;
        if (range.location > _needDownLoadRange.location)
        {
            _currentDownLoadRange = NSMakeRange(_needDownLoadRange.location, range.location - _needDownLoadRange.location);
        }
        else if (i == (_visibleDataRangeInfo.count-1))
        {
            _currentDownLoadRange = NSMakeRange(range.location+range.length+1, _needDownLoadRange.location+_needDownLoadRange.length-range.location-range.length);
        }
    }
    [self downLoadVideoFileData];
}
//范围是否可以相加
BOOL canAddMovieRange(NSRange range1,NSRange range2)
{
    if (range1.length <= 0 || range2.length <= 0)
    {
        return NO;
    }
    
    NSInteger startLocation = MIN(range1.location, range2.location);
    NSInteger endLocation = MAX(range1.location+range1.length, range2.location+range2.length);
    NSInteger maxLength = endLocation - startLocation + 1;
    
    if (maxLength <= (range1.length + range2.length))
    {
        return YES;
    }
    
    return NO;
}
//范围相加
NSRange addMovieRange(NSRange range1,NSRange range2)
{
    NSInteger startLocation = MIN(range1.location, range2.location);
    NSInteger endLocation = MAX(range1.location+range1.length, range2.location+range2.length);
    return NSMakeRange(startLocation, endLocation - startLocation +1);
}
//范围重合
NSRange bothMovieRange(NSRange range1,NSRange range2)
{
    NSInteger startLocation = MAX(range1.location, range2.location);
    NSInteger endLocation = MIN(range1.location+range1.length, range2.location+range2.length);
    return NSMakeRange(startLocation, endLocation - startLocation +1);
}
//给所有请求添加属性
-(void)setupVideoRequestInfo
{
    //每次下载一块数据都是一次请求，把这些请求放到数组，遍历数组
    NSString *mimeType = @"video/mp4";
    CFStringRef contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)(mimeType), NULL);
    for (AVAssetResourceLoadingRequest *loadingRequest in _resourceLoadingRequests)
    {
        loadingRequest.contentInformationRequest.byteRangeAccessSupported = YES;
        loadingRequest.contentInformationRequest.contentType = CFBridgingRelease(contentType);
        loadingRequest.contentInformationRequest.contentLength = _fileLength;
    }
}
//给单个请求添加属性
-(void)setupVideoRequestInfo:(AVAssetResourceLoadingRequest*)loadingRequest
{
    //每次下载一块数据都是一次请求，把这些请求放到数组，遍历数组
    NSString *mimeType = @"video/mp4";
    CFStringRef contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)(mimeType), NULL);
    loadingRequest.contentInformationRequest.byteRangeAccessSupported = YES;
    loadingRequest.contentInformationRequest.contentType = CFBridgingRelease(contentType);
    loadingRequest.contentInformationRequest.contentLength = _fileLength;
}
//下载资源文件
-(void)downLoadVideoFileData
{
    if (_currentDownLoadRange.length <= 0 ||_currentDownLoadRange.location >= _fileLength)
    {
        [self processPendingRequests];
        return;
    }
    
    NSURLComponents *actualURLComponents = [[NSURLComponents alloc] initWithURL:_videoFileURL resolvingAgainstBaseURL:NO];
    actualURLComponents.scheme = @"http";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[actualURLComponents URL] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:20.0];
    
    [request addValue:[NSString stringWithFormat:@"bytes=%ld-%ld",(unsigned long)_currentDownLoadRange.location, (unsigned long)_currentDownLoadRange.length] forHTTPHeaderField:@"Range"];
    
    [self createNewBlankVideoFile];
    _currentFileInfo = [[VideoFileInfo alloc]init];
    _currentFileInfo.filePath = _currentWriteFilePath;
    _currentFileInfo.range = NSMakeRange(_currentDownLoadRange.location, 0);
    [_visibleDataRangeInfo addObject:_currentFileInfo];
    [self resetVisibleDataRange];
    
    _dataTask = [_downLoadSession dataTaskWithRequest:request];
    
    [_dataTask resume];
}
//设置绑定请求数据移除完成的请求
- (void)processPendingRequests
{
    NSMutableArray *requestsCompleted = [NSMutableArray array];  //请求完成的数组
    //每次下载一块数据都是一次请求，把这些请求放到数组，遍历数组
    for (AVAssetResourceLoadingRequest *loadingRequest in _resourceLoadingRequests)
    {
        
        BOOL didRespondCompletely = [self setRespondDataForLoadingDataRequest:loadingRequest.dataRequest]; //判断此次请求的数据是否处理完全
        
        if (didRespondCompletely)
        {
            
            [requestsCompleted addObject:loadingRequest];  //如果完整，把此次请求放进 请求完成的数组
            [loadingRequest finishLoading];
            
        }
    }
    
    [_resourceLoadingRequests removeObjectsInArray:requestsCompleted];   //在所有请求的数组中移除已经完成的
    
}

///给请求设置数据
- (BOOL)setRespondDataForLoadingDataRequest:(AVAssetResourceLoadingDataRequest *)dataRequest
{
    long long startOffset = dataRequest.requestedOffset;
    
    if (dataRequest.currentOffset != 0)
    {
        startOffset = dataRequest.currentOffset;
    }
    
    for (NSInteger i=0; i<_visibleDataRangeInfo.count; i++)
    {
        VideoFileInfo *info = [_visibleDataRangeInfo objectAtIndex:i];
        NSRange range = info.range;
        NSInteger endLocation = range.location + range.length -1;
        if (endLocation>=startOffset && range.location<=startOffset)
        {
            NSInteger dataStartLocation = MAX(startOffset, range.location);
            NSInteger dataEndLocation = MIN(endLocation, startOffset+dataRequest.requestedLength -1);
            if (dataEndLocation >= dataStartLocation)
            {
                NSInteger dataLength = dataEndLocation - dataStartLocation +1;
                NSFileHandle *fileReadHandle = [NSFileHandle fileHandleForReadingAtPath:info.filePath];
                [fileReadHandle seekToFileOffset:dataStartLocation - info.range.location];
                NSMutableData *suportData = [NSMutableData dataWithData:[fileReadHandle readDataOfLength:dataLength]];
                [fileReadHandle closeFile];

                if (dataLength < dataRequest.requestedLength && (_currentFileInfo.range.location <= (endLocation -1)))
                {
                    NSFileHandle *loadingFileReadHandle = [NSFileHandle fileHandleForReadingAtPath:_currentFileInfo.filePath];
                    [loadingFileReadHandle seekToFileOffset:dataEndLocation - info.range.location +1];
                    NSInteger loadingSuportLength = MIN(dataRequest.requestedLength - dataLength, _currentDownLoadLength);
                    [suportData appendData:[loadingFileReadHandle readDataOfLength:loadingSuportLength]];
                    [loadingFileReadHandle closeFile];
                    dataLength += loadingSuportLength;
                }
                
                
                [dataRequest respondWithData:suportData];
                
                if (dataLength >= dataRequest.requestedLength)
                {
                    return YES;
                }
                break;
            }
        }
    }
    
    return NO;
    
    
}
//从新设置已知数据范围
-(void)resetVisibleDataRange
{
    for (NSInteger i=0; i<(_visibleDataRangeInfo.count-1); i++)
    {
        VideoFileInfo *info = [_visibleDataRangeInfo objectAtIndex:i];
        if (info.range.length == 0)
        {
            [_visibleDataRangeInfo removeObjectAtIndex:i];
            --i;
            continue;
        }
        for (NSInteger j = 1; j< _visibleDataRangeInfo.count; j++)
        {
            VideoFileInfo *info1 = [_visibleDataRangeInfo objectAtIndex:i];
            VideoFileInfo *info2 = [_visibleDataRangeInfo objectAtIndex:j];
            if (info1.range.location > info2.range.location)
            {
                [_visibleDataRangeInfo exchangeObjectAtIndex:i withObjectAtIndex:j];
            }
        }
    }
}
//下载一部分完成合并一些可以合并的文件
-(void)resetVisibleVideoFileData
{
    for (NSInteger i=0; i<(_visibleDataRangeInfo.count-1); i++)
    {
        VideoFileInfo *info1 = [_visibleDataRangeInfo objectAtIndex:i];
        VideoFileInfo *info2 = [_visibleDataRangeInfo objectAtIndex:i+1];
        if (canAddMovieRange(info1.range, info2.range))
        {
            NSString *newFilePath = [self mergeFileFrontPart:info1.filePath flowPart:info2.filePath];
            NSRange newRange = addMovieRange(info1.range, info2.range);
            VideoFileInfo *newInfo = [[VideoFileInfo alloc]init];
            newInfo.filePath = newFilePath;
            newInfo.range = newRange;
            [_visibleDataRangeInfo removeObjectAtIndex:i+1];
            [_visibleDataRangeInfo replaceObjectAtIndex:i withObject:newInfo];
            --i;
        }
    }
}
//设置新的起始位置
-(long long)fileLength
{
    return _fileLength;
}
-(void)setPlayStartLocation:(NSInteger)playStartLocation
{
    [_dataTask cancel];
    _dataTask = nil;
    _playStartLocation = playStartLocation;
    [self processPendingRequests];
    [self setDownLoadSettingInfo];
}
#pragma mark 下载代理
-(void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    [_fileWriteHandle seekToFileOffset:_currentDownLoadLength];
    [_fileWriteHandle writeData:data];
    
    _currentDownLoadLength += data.length;
    
    if ([_visibleDataRangeInfo count] >= 1)
    {
        _currentFileInfo.range = NSMakeRange(_currentDownLoadRange.location, _currentDownLoadLength);
    }
    
    [self processPendingRequests];
}
-(void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    _dataTask = nil;
    [self resetVisibleVideoFileData];
    [self processPendingRequests];
    [self setDownLoadSettingInfo];
}
#pragma mark 播放器代理
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest
{
    [_resourceLoadingRequests addObject:loadingRequest];
    if (!_haveGetFileLength)
    {
        [self getVideoFileLength];
    }
    else
    {
        [self setupVideoRequestInfo:loadingRequest];
        
        if (_dataTask == nil)
        {
            [self setDownLoadSettingInfo];
        }
    }
    return YES;
}
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForRenewalOfRequestedResource:(AVAssetResourceRenewalRequest *)renewalRequest
{
    return YES;
}
- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest NS_AVAILABLE(10_9, 7_0)
{
    
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForResponseToAuthenticationChallenge:(NSURLAuthenticationChallenge *)authenticationChallenge
{
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)authenticationChallenge
{
    
}
@end
