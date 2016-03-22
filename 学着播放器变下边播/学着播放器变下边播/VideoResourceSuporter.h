//
//  VideoURLSession.h
//  学着播放器变下边播
//
//  Created by apple on 16/2/24.
//  Copyright © 2016年 cheniue. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface VideoResourceSuporter : NSObject<AVAssetResourceLoaderDelegate,NSURLSessionDataDelegate>
+(instancetype)shareSuporter;
@end
