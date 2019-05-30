#import "handmade_types.h"
#import "AppKit/Appkit.h"

struct MacOSSoundOutput {
    int samplesPerSecond; 
    uint32 bufferSize;
    int16* coreAudioBuffer;
    int16* readCursor;
    int16* writeCursor;
};

extern bool running;
void macOSRefreshBuffer(NSWindow *window);
void renderWeirdGradient();
void macOSRedrawBuffer(NSWindow *window);
