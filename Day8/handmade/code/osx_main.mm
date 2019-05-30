// Handmade Hero OSX
// By Ted Bendixson
//
// OSX Main

#import "handmade_types.h"
#import "osx_main.h"
#import "osx_handmade_windows.h"
#import "osx_handmade_controllers.h"

#import <AppKit/AppKit.h>
#import <AudioToolbox/AudioToolbox.h>

global_variable float globalRenderWidth = 1024;
global_variable float globalRenderHeight = 768;

global_variable uint8 *buffer;
global_variable int bitmapWidth;
global_variable int bitmapHeight;
global_variable int bytesPerPixel = 4;
global_variable int pitch;

global_variable int offsetX = 0;
global_variable int offsetY = 0;

global_variable MacOSSoundOutput soundOutput = {};

bool running = true;

void macOSRefreshBuffer(NSWindow *window) {

    if (buffer) {
        free(buffer);
    }

    bitmapWidth = window.contentView.bounds.size.width;
    bitmapHeight = window.contentView.bounds.size.height;
    pitch = bitmapWidth * bytesPerPixel;
    buffer = (uint8 *)malloc(pitch * bitmapHeight);
}

void renderWeirdGradient() {

    int width = bitmapWidth;
    int height = bitmapHeight;

    uint8 *row = (uint8 *)buffer;

    for ( int y = 0; y < height; ++y) {

        uint8 *pixel = (uint8 *)row;

        for(int x = 0; x < width; ++x) {
            
            /*  Pixel in memory: RR GG BB AA */

            //Red            
            *pixel = 0; 
            ++pixel;  

            //Green
            *pixel = (uint8)y+(uint8)offsetY;
            ++pixel;

            //Blue
            *pixel = (uint8)x+(uint8)offsetX;
            ++pixel;

            //Alpha
            *pixel = 255;
            ++pixel;          
        }

        row += pitch;
    }

}

void macOSRedrawBuffer(NSWindow *window) {
    @autoreleasepool {
        NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: &buffer 
                                  pixelsWide: bitmapWidth
                                  pixelsHigh: bitmapHeight
                                  bitsPerSample: 8
                                  samplesPerPixel: 4
                                  hasAlpha: YES
                                  isPlanar: NO
                                  colorSpaceName: NSDeviceRGBColorSpace
                                  bytesPerRow: pitch
                                  bitsPerPixel: bytesPerPixel * 8] autorelease];

        NSSize imageSize = NSMakeSize(bitmapWidth, bitmapHeight);
        NSImage *image = [[[NSImage alloc] initWithSize: imageSize] autorelease];
        [image addRepresentation: rep];
        window.contentView.layer.contents = image;
    }
}

OSStatus circularBufferRenderCallback(void *inRefCon,
                                      AudioUnitRenderActionFlags *ioActionFlags,
                                      const AudioTimeStamp *inTimeStamp,
                                      uint32 inBusNumber,
                                      uint32 inNumberFrames,
                                      AudioBufferList *ioData) {
    
    int16* leftChannel = (int16*)ioData->mBuffers[0].mData;
    int16* rightChannel= (int16*)ioData->mBuffers[1].mData;

    for (uint32 i = 0; i < inNumberFrames; ++i) {
        int16 *output = soundOutput.readCursor++;
        leftChannel[i] = *output;
        rightChannel[i] = *output;

        if ((char *)soundOutput.readCursor >= (char *)((char *)soundOutput.coreAudioBuffer + soundOutput.bufferSize)) {
            soundOutput.readCursor = soundOutput.coreAudioBuffer;
        }
    }

    return noErr;
}

global_variable AudioComponentInstance audioUnit;

internal_usage
void macOSInitSound() {
  
    //Create a two second circular buffer 
    soundOutput.samplesPerSecond = 48000; 
    soundOutput.bufferSize = soundOutput.samplesPerSecond * sizeof(int16) * 2;

    uint32 maxPossibleOverrun = 8 * 2 * sizeof(int16);

    soundOutput.coreAudioBuffer = (int16*)mmap(0,
                                               soundOutput.bufferSize + maxPossibleOverrun,
                                               PROT_READ|PROT_WRITE,
                                               MAP_PRIVATE|MAP_ANON,
                                               -1,
                                               0);
 
    //todo: (ted) better error handling 
    if (soundOutput.coreAudioBuffer == MAP_FAILED) {
        NSLog(@"Core Audio Buffer mmap error");
        return;
    }

    memset(soundOutput.coreAudioBuffer,
           0,
           soundOutput.bufferSize);

    soundOutput.readCursor = soundOutput.coreAudioBuffer;
    soundOutput.writeCursor = soundOutput.coreAudioBuffer;

    AudioComponentDescription acd;
    acd.componentType = kAudioUnitType_Output;
    acd.componentSubType = kAudioUnitSubType_DefaultOutput;
    acd.componentManufacturer = kAudioUnitManufacturer_Apple;
    acd.componentFlags = 0;
    acd.componentFlagsMask = 0;

    AudioComponent outputComponent = AudioComponentFindNext(NULL, 
                                                            &acd);
    OSStatus status = AudioComponentInstanceNew(outputComponent, 
                                                &audioUnit);
   
    //todo: (ted) - Better error handling 
    if (status != noErr) {
        NSLog(@"There was an error setting up sound");
        return;
    }

    AudioStreamBasicDescription audioDescriptor;
    audioDescriptor.mSampleRate = soundOutput.samplesPerSecond;
    audioDescriptor.mFormatID = kAudioFormatLinearPCM;
    audioDescriptor.mFormatFlags = kAudioFormatFlagIsSignedInteger | 
                                   kAudioFormatFlagIsNonInterleaved | 
                                   kAudioFormatFlagIsPacked; 
    int framesPerPacket = 1;
    int bytesPerFrame = sizeof(int16);
    audioDescriptor.mFramesPerPacket = framesPerPacket;
    audioDescriptor.mChannelsPerFrame = 2; // Stereo sound
    audioDescriptor.mBitsPerChannel = sizeof(int16) * 8;
    audioDescriptor.mBytesPerFrame = bytesPerFrame;
    audioDescriptor.mBytesPerPacket = framesPerPacket * bytesPerFrame; 

    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &audioDescriptor,
                                  sizeof(audioDescriptor));

    //todo: (ted) - Better error handling 
    if (status != noErr) {
        NSLog(@"There was an error setting up the audio unit");
        return;
    }

    AURenderCallbackStruct renderCallback;
    renderCallback.inputProc = circularBufferRenderCallback;

    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Global,
                                  0,
                                  &renderCallback,
                                  sizeof(renderCallback));

    //todo: (ted) - Better error handling 
    if (status != noErr) {
        NSLog(@"There was an error setting up the audio unit");
        return;
    }

    AudioUnitInitialize(audioUnit);
    AudioOutputUnitStart(audioUnit);
}

internal_usage
void updateSoundBuffer() {
  
    int sampleCount = 3200;
 
    //note: (ted) - This is where we would usually get sound samples
    uint32 frequency = 256;
    uint32 period = soundOutput.samplesPerSecond/frequency; 
    uint32 halfPeriod = period/2;
    local_persist uint32 runningSampleIndex = 0;
 
    for (int i = 0; i < sampleCount; ++i) {

        //Write cursor wrapped. Start at the beginning of the Core Audio Buffer.
        if ((char *)soundOutput.writeCursor >= ((char *)soundOutput.coreAudioBuffer + soundOutput.bufferSize)) {
            
            if (soundOutput.readCursor == soundOutput.coreAudioBuffer) {
                break;
            }

            soundOutput.writeCursor = soundOutput.coreAudioBuffer;
        }

        if ((char *)soundOutput.writeCursor == ((char *)soundOutput.readCursor - sizeof(int16))) {
            break;
        }

        int16 sampleValue;

        if((runningSampleIndex%period) > halfPeriod) {
            sampleValue = 5000;
        } else {
            sampleValue = -5000;
        }

        *soundOutput.writeCursor++ = sampleValue;
        runningSampleIndex++; 
    }
}

int main(int argc, const char * argv[]) {

    HandmadeMainWindowDelegate *mainWindowDelegate = [[HandmadeMainWindowDelegate alloc] init];

    NSRect screenRect = [[NSScreen mainScreen] frame];

    NSRect initialFrame = NSMakeRect((screenRect.size.width - globalRenderWidth) * 0.5,
                                     (screenRect.size.height - globalRenderHeight) * 0.5,
                                     globalRenderWidth,
                                     globalRenderHeight);
  
    NSWindow *window = [[HandmadeKeyIgnoringWindow alloc] 
                         initWithContentRect: initialFrame
                         styleMask: NSWindowStyleMaskTitled |
                                    NSWindowStyleMaskClosable |
                                    NSWindowStyleMaskMiniaturizable |
                                    NSWindowStyleMaskResizable 
                         backing: NSBackingStoreBuffered
                         defer: NO];    

    [window setBackgroundColor: NSColor.blackColor];
    [window setTitle: @"Handmade Hero"];
    [window makeKeyAndOrderFront: nil];
    [window setDelegate: mainWindowDelegate];
    window.contentView.wantsLayer = YES;
 
    macOSRefreshBuffer(window);

    ControllerInputSource inputSource = ControllerInputSourceKeyboard;
    [OSXHandmadeController setControllerInputSource: inputSource];
    [OSXHandmadeController initialize];

    macOSInitSound();
 
    while(running) {
   
        renderWeirdGradient();
        macOSRedrawBuffer(window); 
        updateSoundBuffer();

        OSXHandmadeController *controller = [OSXHandmadeController selectedController];
        
        if(controller != nil){
            if(controller.buttonAState == true) {
                offsetX++;       
            }

            if(controller.buttonLeftShoulderState == true) {
                offsetX--;
            }
           
            if(controller.buttonRightShoulderState == true) {
                offsetX++;
            }
 
            if (controller.dpadX == 1) {
                offsetX++;
            }

            if (controller.dpadX == -1) {
                offsetX--;
            }

            if (controller.dpadY == 1) {
                offsetY++;
            }

            if (controller.dpadY == -1) {
                offsetY--;
            }
        }

        NSEvent* event;
        
        do {
            event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                       untilDate: nil
                                          inMode: NSDefaultRunLoopMode
                                         dequeue: YES];
           
            if (event != nil &&
                inputSource == ControllerInputSourceKeyboard &&
                (event.type == NSEventTypeKeyDown ||
                event.type == NSEventTypeKeyUp)) {
                [OSXHandmadeController updateKeyboardControllerWith: event];
            }
 
            switch ([event type]) {
                default:
                    [NSApp sendEvent: event];
            }
        } while (event != nil);
    }
 
    printf("Handmade Finished Running");
}
