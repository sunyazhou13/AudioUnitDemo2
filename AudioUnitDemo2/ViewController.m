//
//  ViewController.m
//  AudioUnitDemo2
//
//  Created by SUNYAZHOU on 2018/5/6.
//  Copyright © 2018年 www.sunyazhou.com. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioUnit/AudioUnit.h>

static const UInt32 InputBus   = 1;
static const UInt32 OutputBus  = 0;
static const UInt32 BufferSize = 2048 * 2 * 10;

@interface ViewController () {
    AudioUnit        audioUnit;
    AudioBufferList *buffList;
    Byte            *buffer;
}
@property (nonatomic, strong) NSInputStream   *inputSteam; //读取本地PCM用
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
}

- (void)createAudioUnit{
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"output" withExtension:@"pcm"];
    self.inputSteam = [NSInputStream inputStreamWithURL:url];
    if (self.inputSteam == nil) { NSLog(@"打开文件失败 %@", url); return;}
    
    [self.inputSteam open];
    
    NSError *error = nil;
    // 配置音频会话
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    if (error) { NSLog(@"setCategory error:%@", error); }
    [[AVAudioSession sharedInstance] setPreferredIOBufferDuration:0.05 error:&error];
    if (error) { NSLog(@"setPreferredIOBufferDuration error:%@", error); }
    
    
    OSStatus status = noErr;
    // buffer list
    uint32_t numberBuffers = 1;
    buffList = (AudioBufferList *)malloc(sizeof(AudioBufferList) + (numberBuffers - 1) * sizeof(AudioBuffer));
    buffList->mNumberBuffers = numberBuffers;
    buffList->mBuffers[0].mNumberChannels = 1;
    buffList->mBuffers[0].mDataByteSize = BufferSize;
    buffList->mBuffers[0].mData = malloc(BufferSize);
    
    
    for (int i =1; i < numberBuffers; ++i) {
        buffList->mBuffers[i].mNumberChannels = 1;
        buffList->mBuffers[i].mDataByteSize = BufferSize;
        buffList->mBuffers[i].mData = malloc(BufferSize);
    }
    
    //创建缓冲区
    buffer = malloc(BufferSize);
    //创建 Audio Unit
    AudioComponentDescription audioDesc;
    audioDesc.componentType = kAudioUnitType_Output;
    audioDesc.componentSubType = kAudioUnitSubType_RemoteIO;
    audioDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    audioDesc.componentFlags = 0;
    audioDesc.componentFlagsMask = 0;
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &audioDesc);
    //这行代码就是创建出一个AudioUnit
    status = AudioComponentInstanceNew(inputComponent, &audioUnit);
    CheckStatus(status, @"AudioUnitGetProperty error", YES);
    
    //设置ASBD
    AudioStreamBasicDescription inputFormat;
    inputFormat.mSampleRate = 44100;
    inputFormat.mFormatID = kAudioFormatLinearPCM;
    inputFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsNonInterleaved;
    inputFormat.mFramesPerPacket = 1;
    inputFormat.mChannelsPerFrame = 1;
    inputFormat.mBytesPerPacket = 2;
    inputFormat.mBytesPerFrame = 2;
    inputFormat.mBitsPerChannel = 16;
    //设置给输入端 配置麦克风输出的数据是什么格式
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  InputBus,
                                  &inputFormat,
                                  sizeof(inputFormat));
    CheckStatus(status, @"AudioUnitGetProperty bus1 output ASBD error", YES);
    
    AudioStreamBasicDescription outputFormat = inputFormat;
    outputFormat.mChannelsPerFrame = 2;
    //设置声音从bus0  output进入的是两路数据
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  OutputBus,
                                  &outputFormat,
                                  sizeof(outputFormat));
    CheckStatus(status, @"AudioUnitGetProperty bus0 input ASBD error", YES);
    
    //启动录制
    UInt32 flag = 1;
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,
                                  InputBus,
                                  &flag,
                                  sizeof(flag));
    CheckStatus(status, @"AudioUnitGetProperty record bus0 input ASBD error", YES);
    
    
    //配置回调
    AURenderCallbackStruct recordCallback;
    recordCallback.inputProc = RecordCallback;
    recordCallback.inputProcRefCon = (__bridge void *)self;
    //给AudioUnit 设置录制回调
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Output,
                                  InputBus,
                                  &recordCallback,
                                  sizeof(recordCallback));
    if (status != noErr) {
        NSLog(@"AudioUnitGetProperty error, ret: %d", status);
    }
    
    AURenderCallbackStruct playCallback;
    playCallback.inputProc = PlayCallback;
    playCallback.inputProcRefCon = (__bridge void *)self;
    //给AudioUnit 设置播放回调
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  OutputBus,
                                  &playCallback,
                                  sizeof(playCallback));
    CheckStatus(status, @"AURenderCallbackStruct error", YES);
    
    //初始化Audio Unit
    OSStatus result = AudioUnitInitialize(audioUnit);
    NSLog(@"初始化Audio Unit:%d", result);
}

static void CheckStatus(OSStatus status, NSString *message, BOOL fatal) {
    if (status != noErr) {
        char fourCC[16];
        *(UInt32 *)fourCC = CFSwapInt32HostToBig(status);
        fourCC[4] = '\0';
        if (isprint(fourCC[0]) && isprint(fourCC[1]) &&
            isprint(fourCC[2]) && isprint(fourCC[4])) {
            NSLog(@"%@:%s",message, fourCC);
        } else {
            NSLog(@"%@:%d",message, (int)status);
        }
        
        if (fatal) {
            exit(-1);
        }
    }
}


#pragma mark -
#pragma mark - callback
static OSStatus RecordCallback(void *inRefCon,
                               AudioUnitRenderActionFlags *ioActionFlags,
                               const AudioTimeStamp *inTimeStamp,
                               UInt32 inBusNumber,
                               UInt32 inNumberFrames,
                               AudioBufferList *ioData)
{
    ViewController *vc = (__bridge ViewController *)inRefCon;
    vc->buffList->mNumberBuffers = 1;
    OSStatus status = AudioUnitRender(vc->audioUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, vc->buffList);
    CheckStatus(status, @"AudioUnitRender error -> RecordCallback", YES);
    
    NSLog(@"Record Size = %d", vc->buffList->mBuffers[0].mDataByteSize);
    //写数据
    [vc writePCMData:vc->buffList->mBuffers[0].mData size:vc->buffList->mBuffers[0].mDataByteSize];
    
    return noErr;
}

static OSStatus PlayCallback(void *inRefCon,
                             AudioUnitRenderActionFlags *ioActionFlags,
                             const AudioTimeStamp *inTimeStamp,
                             UInt32 inBusNumber,
                             UInt32 inNumberFrames,
                             AudioBufferList *ioData) {
    ViewController *vc = (__bridge ViewController *)inRefCon;
    //核心代码 -> 把当前buffList 中的beffer给 ioData.mBuffers[0] 就实现了回放
    memcpy(ioData->mBuffers[0].mData, vc->buffList->mBuffers[0].mData, vc->buffList->mBuffers[0].mDataByteSize);
    ioData->mBuffers[0].mDataByteSize = vc->buffList->mBuffers[0].mDataByteSize;
    
    NSInteger bytes = BufferSize < ioData->mBuffers[1].mDataByteSize * 2 ? BufferSize : ioData->mBuffers[1].mDataByteSize * 2; //
    bytes = [vc.inputSteam read:vc->buffer maxLength:bytes];
    
    for (int i = 0; i < bytes; ++i) {
        ((Byte*)ioData->mBuffers[1].mData)[i/2] = vc->buffer[i];
    }
    ioData->mBuffers[1].mDataByteSize = (UInt32)bytes / 2;
    
    if (ioData->mBuffers[1].mDataByteSize < ioData->mBuffers[0].mDataByteSize) {
        ioData->mBuffers[0].mDataByteSize = ioData->mBuffers[1].mDataByteSize;
    }
    
    
    NSLog(@"Play size = %d", ioData->mBuffers[0].mDataByteSize);
    
    return noErr;
}

- (void)writePCMData:(Byte *)buffer size:(int)size {
    static FILE *file = NULL;
    NSString *path = [NSTemporaryDirectory() stringByAppendingString:@"/record.pcm"];
    if (!file) {
        file = fopen(path.UTF8String, "w");
    }
    fwrite(buffer, size, 1, file);
}

- (IBAction)onRecordButtonClick:(UIButton *)sender {
    sender.selected = !sender.selected;
    if (sender.selected) {
        [ self createAudioUnit];
        AudioOutputUnitStart(audioUnit);
    } else {
        AudioOutputUnitStop(audioUnit);
        AudioUnitUninitialize(audioUnit);
        if (buffList != NULL) {
            if (buffList->mBuffers[0].mData) {
                free(buffList->mBuffers[0].mData);
                buffList->mBuffers[0].mData = NULL;
            }
            free(buffList);
            buffList = NULL;
        }
        [self.inputSteam close];
        AudioComponentInstanceDispose(audioUnit);
    }
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
