//
//  MDHAudioQueue.h
//  MDHAVToolbox
//
//  Created by Apple on 2018/9/14.
//  Copyright © 2018年 马大哈. All rights reserved.
//

/**
 !!!!!!!!!!  仅用于转码 MP3, 不生成caf文件
 */


#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "MDHAudioConfiguration.h"


/**
 @abstract   录音回调
 
 @param filePath    录音文件路径（绝对路径）
 @param duration    时长
 @param fileSize    文件大小（kb）
 @param error       录音或转码是否异常
 */
typedef void(^MDHAudioQueueComplete)(NSString *filePath, NSString *duration, NSString *fileSize, NSError *error);


@interface MDHAudioQueue : NSObject

@property(nonatomic, copy) MDHAudioQueueComplete completeBlock;

/**
 @abstract   判断授权状态
 
 AVAuthorizationStatusNotDetermined   没有询问是否开启麦克风
 AVAuthorizationStatusRestricted      未授权，家长限制
 AVAuthorizationStatusDenied          已经拒绝授权
 AVAuthorizationStatusAuthorized      已经授权过
 */
+ (AVAuthorizationStatus)isAuthorized;

/**
 @abstract  请求系统授权
 */
+ (void)requestAccess:(void (^)(BOOL granted))handler;


/**
 @abstract   初始化
 
 @param configuration   配置
 @param error           参数错误
 */
- (instancetype)initWithConfiguration:(MDHAudioConfiguration *)configuration error:(NSError **)error;

/**
 @abstract   开始录音
 
 @param block  回调
 */
- (void)start:(MDHAudioQueueComplete)block;

/**
 @abstract   继续录音
 */
- (void)reStart;

/**
 @abstract   暂停
 */
- (void)pause;

/**
 @abstract   停止\结束
 */
- (void)stop;

/**
 @abstract   取消
 */
- (void)cancel;

@end
