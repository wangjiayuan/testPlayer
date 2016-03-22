//
//  VideoDataSuportObject.h
//  学着播放器变下边播
//
//  Created by apple on 16/2/25.
//  Copyright © 2016年 cheniue. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#define ERROR_TRY_COUNT (5)

/*
 思路：
 */
@interface VideoDataSuportObject : NSObject
<AVAssetResourceLoaderDelegate,NSURLSessionDataDelegate>
{
    ///视频资源请求数组
    NSMutableArray *_resourceLoadingRequests;
    ///唯一的视频下载线程
    NSURLSessionDataTask *_dataTask;
    ///获取视频资源大小的线程
    NSURLSessionDownloadTask *_fileLengthTask;
    ///视频资源的大小
    long long _fileLength;
    ///是否已经获得文件的大小
    BOOL _haveGetFileLength;
    ////多个下载获得的视频有效数据范围数组
    NSMutableArray *_visibleDataRange;
    ////需要下载的文件范围
    NSRange _needDownLoadRange;
    ////正在执行的下载范围
    NSRange _currentDownLoadRange;
    ////正在下载资源已完成的大小
    long long _currentDownLoadLength;
    ///唯一的资源下载会话
    NSURLSession *_downLoadSession;
    ///下载资源的起始文件地址
    NSURL *_videoFileURL;
    ///文件资源数据写入
    NSFileHandle *_fileWriteHandle;
    ///文件资源数据读取
    NSFileHandle *_fileReadHandle;
    ///文件管理对象
    NSFileManager *_defaultFileManage;
    
}

@property(nonatomic,assign)NSInteger lengthTryCount;
@property(nonatomic,assign)NSInteger fileTryCount;
@property(nonatomic,assign)NSInteger playStartLocation;

-(instancetype)initWithURL:(NSURL*)url;

-(NSString*)saveFilePath;

@end
