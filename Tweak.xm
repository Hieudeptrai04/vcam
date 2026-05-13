// ============================================================
// VcamFullMay — Virtual camera replacement tweak (iOS rootless JB)
//
// Replaces the live camera feed with frames decoded from a user-chosen
// video file. Works in any app that uses AVCaptureSession +
// AVCaptureVideoDataOutput — Zalo, FB, Instagram, TikTok, WhatsApp, etc.
//
// Strategy:
//   1. Hook -[AVCaptureVideoDataOutput setSampleBufferDelegate:queue:]
//   2. Wrap the app's real delegate with a proxy.
//   3. When the camera session fires a frame, the proxy decodes the next
//      frame from the user's video (matched to the session's exact pixel
//      format + dimensions via AVAssetReaderTrackOutput outputSettings)
//      and rebuilds a CMSampleBuffer that keeps the real frame's timing
//      info — so encoders downstream see consistent PTS, no jitter.
//   4. Audio stream from the mic is UNTOUCHED — only video is replaced.
//
// Anti-detection:
//   - NSFileManager hides /var/jb, Cydia/Sileo/Zebra paths.
//   - UIApplication.canOpenURL blocks cydia:// / sileo:// / filza:// URL
//     scheme probes.
//   - dlopen returns NULL for substrate-family dylib paths.
//
// Configuration:
//   /var/jb/etc/vcam/config.plist (optional):
//     <key>videoPath</key>     <string>/var/jb/etc/vcam/video.mp4</string>
//     <key>enabled</key>       <true/>
//
//   Default video path: /var/jb/etc/vcam/video.mp4
// ============================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// ============================================================
// CONFIG
// ============================================================
static NSString *const kVcamConfigPath       = @"/var/jb/etc/vcam/config.plist";
static NSString *const kVcamDefaultVideoPath = @"/var/jb/etc/vcam/video.mp4";

static NSDictionary *vcamConfig(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kVcamConfigPath];
}

static BOOL vcamEnabled(void) {
    NSDictionary *cfg = vcamConfig();
    id e = cfg[@"enabled"];
    if (e && [e respondsToSelector:@selector(boolValue)]) return [e boolValue];
    return YES;  // default on if config missing
}

static NSString *vcamVideoPath(void) {
    NSDictionary *cfg = vcamConfig();
    NSString *p = cfg[@"videoPath"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (p.length > 0 && [fm fileExistsAtPath:p]) return p;
    if ([fm fileExistsAtPath:kVcamDefaultVideoPath]) return kVcamDefaultVideoPath;
    return nil;
}

// ============================================================
// PROXY DELEGATE — replaces camera frames with video frames
// ============================================================
@interface VcamProxyDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, weak)   id<AVCaptureVideoDataOutputSampleBufferDelegate> realDelegate;
@property (nonatomic, copy)   NSString *videoPath;
@property (nonatomic, strong) AVAssetReader *reader;
@property (nonatomic, strong) AVAssetReaderTrackOutput *trackOutput;
@property (nonatomic, assign) int initState;          // 0 unset, 1 ready, 2 failed
@property (nonatomic, assign) size_t  targetW;
@property (nonatomic, assign) size_t  targetH;
@property (nonatomic, assign) OSType  targetPixelFormat;
@end

@implementation VcamProxyDelegate

- (BOOL)setupReader {
    @autoreleasepool {
        AVAsset *asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:self.videoPath]];
        if (!asset) return NO;
        NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (tracks.count == 0) return NO;
        NSError *err = nil;
        AVAssetReader *r = [AVAssetReader assetReaderWithAsset:asset error:&err];
        if (!r) return NO;
        // Request output frames already in the session's expected pixel
        // format + dimensions — no manual colorspace conversion needed.
        NSDictionary *outSettings = @{
            (NSString *)kCVPixelBufferPixelFormatTypeKey: @(self.targetPixelFormat),
            (NSString *)kCVPixelBufferWidthKey:           @(self.targetW),
            (NSString *)kCVPixelBufferHeightKey:          @(self.targetH),
        };
        AVAssetReaderTrackOutput *o = [AVAssetReaderTrackOutput
            assetReaderTrackOutputWithTrack:tracks[0]
                             outputSettings:outSettings];
        if (![r canAddOutput:o]) return NO;
        [r addOutput:o];
        if (![r startReading]) return NO;
        self.reader = r;
        self.trackOutput = o;
        return YES;
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
       didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    // Lazy init on first real frame — gives us the exact target format.
    if (self.initState == 0) {
        CVImageBufferRef ib = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (ib) {
            self.targetW = CVPixelBufferGetWidth(ib);
            self.targetH = CVPixelBufferGetHeight(ib);
            self.targetPixelFormat = CVPixelBufferGetPixelFormatType(ib);
            self.initState = [self setupReader] ? 1 : 2;
        }
    }
    // Fall back to the real frame if init failed or no video.
    if (self.initState != 1) {
        if ([self.realDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            [self.realDelegate captureOutput:output
                       didOutputSampleBuffer:sampleBuffer
                              fromConnection:connection];
        }
        return;
    }

    // Pull next frame; loop video when exhausted.
    CMSampleBufferRef fakeFrame = [self.trackOutput copyNextSampleBuffer];
    if (!fakeFrame) {
        [self.reader cancelReading];
        self.reader = nil;
        self.trackOutput = nil;
        self.initState = [self setupReader] ? 1 : 2;
        fakeFrame = (self.trackOutput
            ? [self.trackOutput copyNextSampleBuffer]
            : NULL);
    }
    if (!fakeFrame) {
        // Reader broken — pass real frame through.
        if ([self.realDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            [self.realDelegate captureOutput:output
                       didOutputSampleBuffer:sampleBuffer
                              fromConnection:connection];
        }
        return;
    }

    // Rebuild a CMSampleBuffer that has the FAKE image but the REAL frame's
    // timing info. Apps' encoders detect "synthetic" timing as a fingerprint —
    // re-using real timing makes the stream look native.
    CMSampleTimingInfo timing;
    CMSampleBufferGetSampleTimingInfo(sampleBuffer, 0, &timing);

    CVImageBufferRef fakeIB = CMSampleBufferGetImageBuffer(fakeFrame);
    CMVideoFormatDescriptionRef desc = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(NULL, fakeIB, &desc);

    CMSampleBufferRef out = NULL;
    OSStatus s = CMSampleBufferCreateForImageBuffer(NULL, fakeIB, YES, NULL,
                                                    NULL, desc, &timing, &out);
    if (desc) CFRelease(desc);
    CFRelease(fakeFrame);

    if (s != noErr || !out) {
        if ([self.realDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            [self.realDelegate captureOutput:output
                       didOutputSampleBuffer:sampleBuffer
                              fromConnection:connection];
        }
        return;
    }

    [self.realDelegate captureOutput:output
               didOutputSampleBuffer:out
                      fromConnection:connection];
    CFRelease(out);
}

// Forward drop notifications transparently.
- (void)captureOutput:(AVCaptureOutput *)output
       didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    if ([self.realDelegate respondsToSelector:_cmd]) {
        [self.realDelegate captureOutput:output
                     didDropSampleBuffer:sampleBuffer
                          fromConnection:connection];
    }
}

@end

// ============================================================
// CAMERA HOOK
// ============================================================
static const void *kVcamProxyKey = &kVcamProxyKey;

%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
                            queue:(dispatch_queue_t)queue
{
    if (!vcamEnabled() || !delegate) { %orig; return; }
    NSString *video = vcamVideoPath();
    if (!video) { %orig; return; }

    VcamProxyDelegate *proxy = [VcamProxyDelegate new];
    proxy.realDelegate = delegate;
    proxy.videoPath    = video;

    // Retain proxy on the output so it lives as long as the session does.
    objc_setAssociatedObject(self, kVcamProxyKey, proxy,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    %orig(proxy, queue);
}

%end

// ============================================================
// JB HIDE — filesystem path probes
// ============================================================
static NSArray *vcamHiddenPaths(void) {
    static NSArray *paths = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        paths = @[
            @"/var/jb", @"/private/var/jb",
            @"/Applications/Cydia.app", @"/Applications/Sileo.app",
            @"/Applications/Zebra.app", @"/Applications/Installer.app",
            @"/Library/MobileSubstrate", @"/usr/lib/TweakInject",
            @"/usr/sbin/sshd", @"/usr/bin/ssh",
            @"/.installed_dopamine", @"/.installed_palera1n",
            @"/var/binpack", @"/var/lib/cydia",
            @"/etc/apt", @"/var/lib/apt", @"/var/lib/dpkg",
            @"/bin/bash", @"/bin/sh",
        ];
    });
    return paths;
}

%hook NSFileManager

- (BOOL)fileExistsAtPath:(NSString *)path {
    if (path.length > 0) {
        for (NSString *p in vcamHiddenPaths()) {
            if ([path hasPrefix:p]) return NO;
        }
    }
    return %orig;
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if (path.length > 0) {
        for (NSString *p in vcamHiddenPaths()) {
            if ([path hasPrefix:p]) return NO;
        }
    }
    return %orig;
}

%end

// ============================================================
// JB HIDE — URL scheme probes (cydia://, sileo://, filza://)
// ============================================================
%hook UIApplication

- (BOOL)canOpenURL:(NSURL *)url {
    NSString *scheme = url.scheme;
    if (scheme.length > 0) {
        static NSArray *blocked = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            blocked = @[ @"cydia", @"sileo", @"zbra", @"filza",
                         @"undecimus", @"activator", @"flex" ];
        });
        for (NSString *s in blocked) {
            if ([scheme isEqualToString:s]) return NO;
        }
    }
    return %orig;
}

%end

// ============================================================
// JB HIDE — block dlopen of substrate / hook engine dylibs
// ============================================================
typedef void *(*dlopen_t)(const char *path, int mode);
static dlopen_t orig_dlopen = NULL;

static void *vcam_dlopen(const char *path, int mode) {
    if (path) {
        static const char *blocked[] = {
            "Substrate", "TweakInject", "ElleKit", "libhooker",
            "substitute", "pspawn_payload", "VcamFullMay", NULL
        };
        for (const char **p = blocked; *p; p++) {
            if (strstr(path, *p)) return NULL;
        }
    }
    return orig_dlopen ? orig_dlopen(path, mode) : NULL;
}

// ============================================================
// CTOR
// ============================================================
%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        NSLog(@"[VcamFullMay] loaded in %@", bid);

        // Hook dlopen at runtime — Logos hooks Obj-C; %hookf works for C.
        void *handle = dlopen(NULL, RTLD_NOW);
        if (handle) {
            void *sym = dlsym(handle, "dlopen");
            if (sym) {
                // MSHookFunction declaration (substrate.h not always available
                // in rootless SDK — declare manually).
                extern void MSHookFunction(void *symbol, void *replace, void **result);
                MSHookFunction(sym, (void *)vcam_dlopen, (void **)&orig_dlopen);
            }
        }
    }
}
