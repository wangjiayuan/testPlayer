//
//  VideoDataSuportObject.m
//  学着播放器变下边播
//
//  Created by apple on 16/2/25.
//  Copyright © 2016年 cheniue. All rights reserved.
//

#import "VideoDataSuportObject.h"
#import <MobileCoreServices/MobileCoreServices.h>

@implementation VideoDataSuportObject
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
        _visibleDataRange = [[NSMutableArray alloc]initWithCapacity:0];
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
        
        self.lengthTryCount = 0;
        self.fileTryCount = 0;
        self.playStartLocation = 0;
    }
    return self;
}
#pragma mark 操作函数
-(NSString*)saveFilePath
{
    NSString *fileName = [NSString stringWithFormat:@"%@.mp4",@((NSUInteger)self)];
    NSString *document = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject;
    NSString *filePath = [document stringByAppendingPathComponent:fileName];
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
            [self createBlankFile];
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
-(void)createBlankFile
{
    NSString *filePath = [self saveFilePath];
    [_defaultFileManage createFileAtPath:filePath contents:nil attributes:nil];
    if ([_defaultFileManage fileExistsAtPath:filePath])
    {
        _fileWriteHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
        _fileReadHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
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
    for (NSInteger i=0; i<_visibleDataRange.count; i++)
    {
        NSValue *value = [_visibleDataRange objectAtIndex:i];
        NSRange range = [value rangeValue];
        if (range.location > _needDownLoadRange.location)
        {
            _currentDownLoadRange = NSMakeRange(_needDownLoadRange.location, range.location - _needDownLoadRange.location);
        }
        else if (i == (_visibleDataRange.count-1))
        {
            _currentDownLoadRange = NSMakeRange(range.location+range.length+1, _needDownLoadRange.location+_needDownLoadRange.length-range.location-range.length);
        }
    }
    [self downLoadVideoFileData];
}
//范围是否可以相加
BOOL canAddRange(NSRange range1,NSRange range2)
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
NSRange addRange(NSRange range1,NSRange range2)
{
    NSInteger startLocation = MIN(range1.location, range2.location);
    NSInteger endLocation = MAX(range1.location+range1.length, range2.location+range2.length);
    return NSMakeRange(startLocation, endLocation - startLocation +1);
}
//范围重合
NSRange bothRange(NSRange range1,NSRange range2)
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
    
    for (NSInteger i=0; i<_visibleDataRange.count; i++)
    {
        NSValue *value = [_visibleDataRange objectAtIndex:i];
        NSRange range = [value rangeValue];
        NSInteger endLocation = range.location + range.length;
        if (endLocation>=startOffset && range.location<=startOffset)
        {
            NSInteger dataStartLocation = MAX(startOffset, range.location);
            NSInteger dataEndLocation = MIN(endLocation, startOffset+dataRequest.requestedLength -1);
            if (dataEndLocation >= dataStartLocation)
            {
                NSInteger dataLength = dataEndLocation - dataStartLocation +1;
                [_fileReadHandle seekToFileOffset:dataStartLocation];
                NSData *suportData = [_fileReadHandle readDataOfLength:dataLength];
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
    NSRange loadingDataRange = NSMakeRange(_currentDownLoadRange.location, _currentDownLoadLength);
    [_visibleDataRange addObject:[NSValue valueWithRange:loadingDataRange]];
    for (NSInteger i=0; i<(_visibleDataRange.count-1); i++)
    {
        NSValue *value1 = [_visibleDataRange objectAtIndex:i];
        NSValue *value2 = [_visibleDataRange objectAtIndex:i+1];
        NSRange range1 = [value1 rangeValue];
        NSRange range2 = [value2 rangeValue];
        if (canAddRange(range1, range2))
        {
            NSRange newRange = addRange(range1, range2);
            [_visibleDataRange removeObjectAtIndex:i+1];
            [_visibleDataRange replaceObjectAtIndex:i withObject:[NSValue valueWithRange:newRange]];
            --i;
        }
    }
}
#pragma mark 下载代理
-(void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    NSFileManager *manage = [NSFileManager defaultManager];
    NSString *filePath = [self saveFilePath];
    if ([manage fileExistsAtPath:filePath])
    {
        [_fileWriteHandle seekToFileOffset:_currentDownLoadRange.location+_currentDownLoadLength];
        [_fileWriteHandle writeData:data];
    }
    _currentDownLoadLength += data.length;
    
    [self resetVisibleDataRange];
    
    [self processPendingRequests];
}
-(void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    _dataTask = nil;
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
