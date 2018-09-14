//
//  MDHMP3Conversion.h
//  MDHAVFoudation
//
//  Created by Apple on 2018/8/7.
//  Copyright © 2018年 马大哈. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 @abstract   转码回调
 
 @param deleteFile   正常结束&取消操作
 */
typedef void(^MDHMP3CompleteBlock)(BOOL deleteFile);

@class MDHAudioConfiguration;
@interface MDHMP3Conversion : NSObject

@property(nonatomic, copy) MDHMP3CompleteBlock completeBlock;


/**
 @abstract   初始化
 
 @param configuration   配置
 @param error           参数错误
 */
- (instancetype)initWithConfiguration:(MDHAudioConfiguration *)configuration error:(NSError **)error;

/**
 @abstract   开始转码
 
 @param cBlock  回调
 */
- (void)start:(MDHMP3CompleteBlock)cBlock;

/**
 @abstract   继续转码
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
