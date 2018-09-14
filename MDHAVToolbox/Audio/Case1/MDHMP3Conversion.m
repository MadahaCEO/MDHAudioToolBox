//
//  MDHMP3Conversion.m
//  MDHAVFoudation
//
//  Created by Apple on 2018/8/7.
//  Copyright © 2018年 马大哈. All rights reserved.
//

#import "MDHMP3Conversion.h"
#import "MDHAudioConfiguration.h"
#import "lame.h"


@interface MDHMP3Conversion ()
{
    int read, write;
    FILE *pcm;
    FILE *mp3;
    
    lame_t lame;
    
    long curpos;

}

@property(nonatomic, strong) MDHAudioConfiguration *audioConfiguration;

// 是否跳过噪音
@property(nonatomic, assign) BOOL isSkipPCMHeader;
// 是否需要关闭文件
@property(nonatomic, assign) BOOL needClosed;
// 是否继续转码（while循环中）
@property(nonatomic, assign) BOOL keepConverting;
// 取消操作
@property(nonatomic, assign) BOOL cancelAction;

@end


@implementation MDHMP3Conversion


- (void)dealloc {
    NSLog(@"MDHMP3Conversion---------- dealloc");
}


- (instancetype)initWithConfiguration:(MDHAudioConfiguration *)configuration error:(NSError **)error {

    self = [super init];
    if (self) {
        
        _audioConfiguration = configuration;
        
        /*
         文件顺利打开后，指向该流的文件指针就会被返回。如果文件打开失败则返回 NULL，并把错误代码存在 error 中。
         pcm & mp3 是两个文件指针，执行转码过程中文件指针不停移动
         
         rb:  以只读方式打开一个二进制文件文件，该文件必须存在。
         wb+: 以读/写方式打开或建立一个二进制文件，允许读和写。
         */
        pcm = fopen([_audioConfiguration.cafFilePath  cStringUsingEncoding:NSASCIIStringEncoding], "rb");
        mp3 = fopen([_audioConfiguration.mp3FilePath  cStringUsingEncoding:NSASCIIStringEncoding], "wb+");
        
        /*
         转码参数：采样率、通道、码率
         */
        lame = lame_init();
        lame_set_in_samplerate(lame, _audioConfiguration.sampleRate);
        lame_set_num_channels(lame, _audioConfiguration.channel);
        lame_set_VBR(lame, vbr_default);
        lame_set_brate(lame, _audioConfiguration.bitRate);
        lame_set_quality(lame,_audioConfiguration.quality);

       
        /*
         头信息===》生成的mp3文件解析头信息乱码===》why？
         */
        id3tag_init(lame);
        id3tag_add_v2(lame);
        id3tag_space_v1(lame);
        id3tag_pad_v2(lame);
        id3tag_set_artist(lame, [@"作者" cStringUsingEncoding:NSUTF16StringEncoding]);
        id3tag_set_album(lame, [@"专辑" cStringUsingEncoding:NSUTF16StringEncoding]);
        id3tag_set_title(lame, [@"歌名" cStringUsingEncoding:NSUTF16StringEncoding]);
        id3tag_set_track(lame, [@"音轨" cStringUsingEncoding:NSUTF16StringEncoding]);
        id3tag_set_year(lame, [[NSDate date].description cStringUsingEncoding:NSUTF16StringEncoding]);
        id3tag_set_comment(lame, [@"备注" cStringUsingEncoding:NSUTF16StringEncoding]);
        id3tag_set_genre(lame,[@"Blues" cStringUsingEncoding:NSUTF16StringEncoding]);
        
        
        /*
         1KB 可以， 大于1kb造成转码失败。===》why ？
         */
        NSString *imagePath = [[NSBundle mainBundle] pathForResource:@"test_clean" ofType:@"png"];
        
        int ret = -1;
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
            ret = 6;
        }
        FILE *fpi = fopen([imagePath  cStringUsingEncoding:NSASCIIStringEncoding], "rb");
        if (!fpi) {
            ret = 1;
        } else {
            size_t size;
            
            fseek(fpi, 0, SEEK_END);
            size = ftell(fpi);
            fseek(fpi, 0, SEEK_SET);
            char *albumart = (char *)malloc(size);
            if (!albumart) {
                ret = 2;
            } else {
                if (fread(albumart, 1, size, fpi) != size) {
                    ret = 3;
                } else {
                    ret = id3tag_set_albumart(lame, albumart, size) ? 4 : 0;
                }
                free(albumart);
            }
            fclose(fpi);
        }
        
        
        int result = lame_init_params(lame);
        if (result == -1 && error != NULL) {
            *error = [NSError errorWithDomain:@"com.lame.error"
                                         code:0
                                     userInfo:@{NSLocalizedDescriptionKey:@"lame 初始化失败"}];
            return nil;
        }
    }
    
    return self;
}

- (void)convert {
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        @try {
            
            const int PCM_SIZE = 8192; // 相当于8192箱啤酒，一箱16瓶（啤酒=字节，8192个16字节的数据长度）
            const int MP3_SIZE = 8192;
            short int pcm_buffer[PCM_SIZE * _audioConfiguration.channel]; // 填充 PCM_SIZE * self.realChannels 个pcm格式数据元素的数组
            unsigned char mp3_buffer[MP3_SIZE]; // 填充 MP3_SIZE 个mp3格式数据元素的数组
            
            do {
                
                /*
                 ftell
                 得到文件位置指针当前位置相对于文件首的偏移字节数
                 
                 fseek
                 第一个参数stream为文件指针
                 第二个参数offset为偏移量，《正数》表示正向偏移，《负数》表示负向偏移
                 第三个参数origin设定从文件的哪里开始偏移,可能取值为：SEEK_CUR（文件开头）、 SEEK_END（文件结尾） 、 SEEK_SET（当前位置）

                 1.curpos 得到当前文件指针偏移位置
                 2.start = curpos
                 3.跳到文件尾部
                 4.endPos = 文件指针偏移位置
                 5.length = 当前文件的总字节数
                 6.文件指针偏移到距离当前位置 curpos 字节处
                 */
                curpos = ftell(pcm);
                long startPos = ftell(pcm);
                fseek(pcm, 0, SEEK_END);
                long endPos = ftell(pcm);
                long length = endPos - startPos;
                fseek(pcm, curpos, SEEK_SET);
                
                /*
                 当前文件流中字节是否大于 设定的字节数据长度
                 self.realChannels===》why?
                                  ===》转码的时候参数说明 number of samples per channel （每个通道的样本，so，2通道个需要乘以2）
                 sizeof(short int)===》计算 short int 占用的字节数
                 */
                if (length > PCM_SIZE * _audioConfiguration.channel * sizeof(short int)) {
                    
                    if (!self.isSkipPCMHeader) {
                        // 跳过噪音
                        fseek(pcm, 4 * 1024, SEEK_CUR);
                        self.isSkipPCMHeader = YES;
                    }
                    
                    /*
                     fread -> 文件指针根据读取长度向后偏移
                     第一个参数:用于接收数据的内存地址
                     第二个参数:要读的每个数据项的字节数，单位是字节
                     第三个参数:要读count个数据项，每个数据项size个字节.
                     第四个参数:输入流
                     
                     从 pcm 文件流中读取 PCM_SIZE 个 self.realChannels * sizeof(short int) 字节的数据存到 pcm_buffer 中
                     
                     pcm 文件指针会偏移
                     */
                    read = (int)fread(pcm_buffer, _audioConfiguration.channel * sizeof(short int), PCM_SIZE, pcm);
                   
                    NSLog(@"pcf_buffer---------- %d",read);

                    if (_audioConfiguration.channel == 1) {
                        /*
                         lame_encode_buffer -> 将输入的PCM数据编码成MP3数据。
                         第一个参数: lame 对象
                         第二个参数: 左声道pcm数据
                         第三个参数: 右声道pcm数据
                         第四个参数: 每个声道的 样本数量
                         第五个参数: mp3 数据
                         第六个参数: 元素个数
                         */
                        write = lame_encode_buffer(lame, pcm_buffer, NULL, read, mp3_buffer, MP3_SIZE);
                        
                    } else {
                        /*
                         lame_encode_buffer_interleaved -> 将输入的PCM数据编码成MP3数据。
                         第一个参数: lame 对象
                         第二个参数: 左&右声道pcm交叉数据
                         第三个参数: 每个声道的 样本数量
                         第四个参数: mp3 数据
                         第五个参数: 元素个数
                         */
                        write = lame_encode_buffer_interleaved(lame, pcm_buffer, read, mp3_buffer, MP3_SIZE);
                    }
                    
                    if (write < 0) {
                        // 直接跳出循环（转码异常,等同于取消操作。）
                        self.cancelAction    = YES;
                        self.keepConverting  = NO;
                    }
                    
                    NSLog(@"mp3_buffer---------- %d",write);

                    /*
                     fwrite -> 文件指针根据读取长度向后偏移
                     第一个参数:是一个指针，对fwrite来说，是要获取数据的地址；
                     第二个参数:要写入内容的单字节数；
                     第三个参数:要进行写入size字节的数据项的个数；
                     第四个参数:目标文件指针
                     
                     从 mp3_buffer 中读取 1 个 write 字节的数据 写入 mp3 文件流中
                     */
                    fwrite(mp3_buffer, write, 1, mp3);
                } else {
                    
                    [NSThread sleepForTimeInterval:0.1];
                }
            } while (self.keepConverting);
            
            read = (int)fread(pcm_buffer, _audioConfiguration.channel * sizeof(short int), PCM_SIZE, pcm);
           
            /*
             lame_encode_flush -> 将mp3buffer中的MP3数据输出
             */
            write = lame_encode_flush(lame, mp3_buffer, MP3_SIZE);
            
            NSLog(@"flush_mp3_buffer---------- %d",write);

            if (self.needClosed) {
                [self lameClosed];
            }
        } @catch (NSException *exception) {
            NSLog(@"%@", [exception description]);

        } @finally {
        }
    });
}

- (void)start:(MDHMP3CompleteBlock)cBlock {
    
    self.completeBlock = cBlock;
    
    self.keepConverting  = YES;
    self.isSkipPCMHeader = NO;

    [self convert];
}

- (void)pause {
    
    self.needClosed  = NO;
    self.keepConverting = NO;
}

- (void)reStart {
    
    self.keepConverting  = YES;
    self.isSkipPCMHeader = NO;
    
    [self convert];
}

- (void)stop {
    
    // 暂停，直接停止
    if (!self.keepConverting) {
        [self lameClosed];
        return;
    }
    
    self.keepConverting = NO;
    self.needClosed     = YES;
}

- (void)cancel {
    
    self.cancelAction  = YES;

    // 暂停，直接取消
    if (!self.keepConverting) {
        [self lameClosed];
        return;
    }
    
    self.keepConverting = NO;
    self.needClosed     = YES;
}

- (void)lameClosed {
    
    lame_mp3_tags_fid(lame, mp3);
    
    lame_close(lame);
    fclose(mp3);
    fclose(pcm);
   
    if (self.completeBlock) {
        self.completeBlock(self.cancelAction);
    }
}


@end
