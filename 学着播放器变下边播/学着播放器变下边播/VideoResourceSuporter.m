//
//  VideoURLSession.m
//  学着播放器变下边播
//
//  Created by apple on 16/2/24.
//  Copyright © 2016年 cheniue. All rights reserved.
//

#import "VideoResourceSuporter.h"
#import <MobileCoreServices/MobileCoreServices.h>

@interface VideoResourceSuporter ()
{
    NSMutableArray *_resourceLoadingRequests;
    long long _fileLength;
    BOOL _haveGetFileLength;
    NSMutableData *_fileData;
}
@end

@implementation VideoResourceSuporter
-(instancetype)init
{
    self = [super init];
    if (self)
    {
        _resourceLoadingRequests = [NSMutableArray array];
        _fileLength = 0;
        _haveGetFileLength = NO;
        _fileData = [NSMutableData data];
    }
    return self;
}
#pragma mark 操作函数
+(instancetype)shareSuporter
{
    static VideoResourceSuporter *suporter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        suporter = [[VideoResourceSuporter alloc]init];
    });
    return suporter;
}
+(NSURLSession *)shareVideoSession
{
    static NSURLSession *session;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (session == nil)
        {
            session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:[VideoResourceSuporter shareSuporter] delegateQueue:[NSOperationQueue mainQueue]];
        }
    });
    return session;
}
-(void)getFilelength:(NSURL *)url
{
    NSURLComponents *actualURLComponents = [[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:NO];
    actualURLComponents.scheme = @"http";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[actualURLComponents URL]];
    [request setHTTPMethod:@"HEAD"];
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithRequest:request completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        if (error == nil)
        {
            _fileLength = [response expectedContentLength];
            _haveGetFileLength = YES;
            [self setupVideoRequestInfo];
            [self requestVideoData];
        }
        
    }];
    [task resume];
}
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
-(void)setupVideoRequestInfo:(AVAssetResourceLoadingRequest*)loadingRequest
{
    //每次下载一块数据都是一次请求，把这些请求放到数组，遍历数组
    NSString *mimeType = @"video/mp4";
    CFStringRef contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)(mimeType), NULL);
    loadingRequest.contentInformationRequest.byteRangeAccessSupported = YES;
    loadingRequest.contentInformationRequest.contentType = CFBridgingRelease(contentType);
    loadingRequest.contentInformationRequest.contentLength = _fileLength;
}

-(void)requestVideoData
{
    if (_fileData.length>0)
    {
        return;
    }
    AVAssetResourceLoadingRequest *loadingRequest = [_resourceLoadingRequests firstObject];
//    NSRange range = NSMakeRange((NSUInteger)loadingRequest.dataRequest.currentOffset, NSUIntegerMax);
    NSURL *url = [loadingRequest.request URL];
    NSURLComponents *actualURLComponents = [[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:NO];
    actualURLComponents.scheme = @"http";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[actualURLComponents URL] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:20.0];
    [request addValue:[NSString stringWithFormat:@"bytes=%ld-%ld",(unsigned long)0, (unsigned long)_fileLength - 1] forHTTPHeaderField:@"Range"];
    
    NSURLSessionDataTask *task = [[VideoResourceSuporter shareVideoSession] dataTaskWithRequest:request];
    
    [task resume];
}

- (void)processPendingRequests
{
    NSMutableArray *requestsCompleted = [NSMutableArray array];  //请求完成的数组
    //每次下载一块数据都是一次请求，把这些请求放到数组，遍历数组
    for (AVAssetResourceLoadingRequest *loadingRequest in _resourceLoadingRequests)
    {
        
        BOOL didRespondCompletely = [self respondWithDataForRequest:loadingRequest.dataRequest]; //判断此次请求的数据是否处理完全
        
        if (didRespondCompletely)
        {
            
            [requestsCompleted addObject:loadingRequest];  //如果完整，把此次请求放进 请求完成的数组
            [loadingRequest finishLoading];
            
        }
    }
    
    [_resourceLoadingRequests removeObjectsInArray:requestsCompleted];   //在所有请求的数组中移除已经完成的
    
}


- (BOOL)respondWithDataForRequest:(AVAssetResourceLoadingDataRequest *)dataRequest
{
    long long startOffset = dataRequest.requestedOffset;
    
    if (dataRequest.currentOffset != 0)
    {
        startOffset = dataRequest.currentOffset;
    }
    
    if ((_fileData.length) < startOffset)
    {
        return NO;
    }
    
    if (startOffset < 0)
    {
        return NO;
    }
    
    // This is the total data we have from startOffset to whatever has been downloaded so far
    NSUInteger unreadBytes = _fileData.length - (NSInteger)startOffset;
    
    // Respond with whatever is available if we can't satisfy the request fully yet
    NSUInteger numberOfBytesToRespondWith = MIN((NSUInteger)dataRequest.requestedLength, unreadBytes);
    
    
    [dataRequest respondWithData:[_fileData subdataWithRange:NSMakeRange((NSUInteger)startOffset, (NSUInteger)numberOfBytesToRespondWith)]];
    
    
    
    long long endOffset = startOffset + dataRequest.requestedLength;
    BOOL didRespondFully = _fileData.length >= endOffset;
    
    return didRespondFully;
    
    
}

#pragma mark 下载代理
-(void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
    [_fileData appendData:data];
    
    [self processPendingRequests];
}
-(void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    [self requestVideoData];
}
#pragma mark 播放器代理
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest
{
    [_resourceLoadingRequests addObject:loadingRequest];
    if (!_haveGetFileLength)
    {
        [self getFilelength:loadingRequest.request.URL];
    }
    else
    {
        [self setupVideoRequestInfo:loadingRequest];
        
        if ([_resourceLoadingRequests count]==1)
        {
            [self requestVideoData];
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
