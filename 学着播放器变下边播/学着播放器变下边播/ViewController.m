//
//  ViewController.m
//  学着播放器变下边播
//
//  Created by apple on 16/2/24.
//  Copyright © 2016年 cheniue. All rights reserved.
//

#import "ViewController.h"
#import "VideoResourceSuporter.h"
#import "VideoDataSuportObject.h"
#import "MovieDataController.h"

@interface ViewController ()
{
    AVPlayer *player;
    AVPlayerItem *playerItem;
    AVURLAsset *asset;
    UISlider *progressSlider;
//    VideoResourceSuporter *suporter;
//    VideoDataSuportObject *dataObject;
    MovieDataController *controller;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:[NSURL URLWithString:@"http://zyvideo1.oss-cn-qingdao.aliyuncs.com/zyvd/7c/de/04ec95f4fd42d9d01f63b9683ad0"] resolvingAgainstBaseURL:NO];
    components.scheme = @"streaming";
//    suporter = [VideoResourceSuporter shareSuporter];//必须是全局变量，否则不回调
//    dataObject = [[VideoDataSuportObject alloc]initWithURL:[components URL]];
    controller = [[MovieDataController alloc]initWithURL:[components URL]];
    asset = [AVURLAsset URLAssetWithURL:[components URL] options:nil];
//    [asset.resourceLoader setDelegate:suporter queue:dispatch_get_main_queue()];
//    [asset.resourceLoader setDelegate:dataObject queue:dispatch_get_main_queue()];
    [asset.resourceLoader setDelegate:controller queue:dispatch_get_main_queue()];
    playerItem = [AVPlayerItem playerItemWithAsset:asset];
    player = [AVPlayer playerWithPlayerItem:playerItem];
    AVPlayerLayer *playLayer = [AVPlayerLayer playerLayerWithPlayer:player];
    [playLayer setFrame:self.view.bounds];
    [playLayer setBackgroundColor:[UIColor yellowColor].CGColor];
    [player play];
    [self.view.layer addSublayer:playLayer];
    
    [self.view bringSubviewToFront:self.functionButton];
    
    
//    progressSlider = [[UISlider alloc]initWithFrame:CGRectMake(40, 50, 240, 30)];
//    [progressSlider addTarget:self action:@selector(progressChange) forControlEvents:UIControlEventValueChanged];
//    [self.view addSubview:progressSlider];

}
-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    float seconds = playerItem.duration.value*0.5;
    [player pause];
    [player seekToTime:CMTimeMakeWithSeconds(seconds, NSEC_PER_SEC) completionHandler:^(BOOL finished) {
        [controller setPlayStartLocation:(NSInteger)([controller fileLength]*(progressSlider.value/progressSlider.maximumValue))];
        [player play];
        
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
