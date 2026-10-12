#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static const char *kTokenCounterKey = "kTokenCounterKey";
static const char *kActiveTokenKey = "kActiveTokenKey";
static NSString *const kAudioDidStartNotification = @"kEasyDictPatchAudioDidStartNotification";

// MARK: - Method Swizzling Helper

static void SwizzleInstanceMethod(Class cls, SEL origSel, SEL newSel) {
    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method newMethod = class_getInstanceMethod(cls, newSel);
    if (!origMethod || !newMethod) {
        NSLog(@"[EasyDict-Patch] Failed to find methods for swizzling: %s / %s on %@",
              sel_getName(origSel), sel_getName(newSel), cls);
        return;
    }
    method_exchangeImplementations(origMethod, newMethod);
    NSLog(@"[EasyDict-Patch] Successfully swizzled %s on %@", sel_getName(origSel), cls);
}

// MARK: - EZBaseQueryViewController Swizzling

@interface NSObject (EZBaseQueryVCInterface)
- (id)config;
- (NSString *)queryText;
- (void)stopPlayingQueryText;
- (void)togglePlayQueryText:(BOOL)play;
@end

@implementation NSObject (EZBaseQueryVCPatch)

- (void)patched_autoPlayEnglishWordAudio {
    BOOL autoPlayEnabled = YES;
    @try {
        id config = [self valueForKey:@"config"];
        if (config) {
            autoPlayEnabled = [[config valueForKey:@"autoPlayAudio"] boolValue];
        }
    } @catch (NSException *e) {
        autoPlayEnabled = YES;
    }

    if (!autoPlayEnabled) {
        return;
    }

    NSString *text = nil;
    @try {
        text = [self valueForKey:@"queryText"];
    } @catch (NSException *e) {}

    if (!text || text.length == 0) {
        return;
    }

    NSLog(@"[EasyDict-Patch] autoPlayAudio triggered for text (length: %lu): %@",
          (unsigned long)text.length, text.length > 40 ? [text substringToIndex:40] : text);

    // Stop any existing playing audio first to prevent overlapping
    if ([self respondsToSelector:@selector(stopPlayingQueryText)]) {
        [self stopPlayingQueryText];
    }

    // Toggle query text pronunciation for any length (words, phrases, sentences, paragraphs)
    if ([self respondsToSelector:@selector(togglePlayQueryText:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(togglePlayQueryText:), YES);
    }
}

- (void)patched_startQueryText:(NSString *)text actionType:(id)actionType {
    if ([self respondsToSelector:@selector(stopPlayingQueryText)]) {
        [self stopPlayingQueryText];
    }
    // Call original method
    ((void (*)(id, SEL, id, id))objc_msgSend)(self, @selector(patched_startQueryText:actionType:), text, actionType);
}

- (void)patched_queryCurrentModel {
    if ([self respondsToSelector:@selector(stopPlayingQueryText)]) {
        [self stopPlayingQueryText];
    }
    // Call original method
    ((void (*)(id, SEL))objc_msgSend)(self, @selector(patched_queryCurrentModel));
}

@end

// MARK: - EZAudioPlayer Swizzling

@implementation NSObject (EZAudioPlayerPatch)

- (void)patched_playTextAudio:(NSString *)text
                     language:(id)language
                       accent:(id)accent
                     audioURL:(NSString *)audioURL
            designatedService:(id)designatedService
                     forceURL:(BOOL)forceURL {
    if (!text || text.length == 0) {
        return;
    }

    if (!audioURL || audioURL.length == 0) {
        // Initial play request on this audio player
        NSNumber *counterNum = objc_getAssociatedObject(self, kTokenCounterKey);
        uint64_t counter = counterNum ? [counterNum unsignedLongLongValue] + 1 : 1;
        objc_setAssociatedObject(self, kTokenCounterKey, @(counter), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kActiveTokenKey, @(counter), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // Notify other audio player instances to stop
        [[NSNotificationCenter defaultCenter] postNotificationName:kAudioDidStartNotification object:self];

        // Call original method
        ((void (*)(id, SEL, id, id, id, id, id, BOOL))objc_msgSend)(
            self, @selector(patched_playTextAudio:language:accent:audioURL:designatedService:forceURL:),
            text, language, accent, audioURL, designatedService, forceURL);
    } else {
        // Callback returning with audioURL on this audio player
        NSNumber *activeToken = objc_getAssociatedObject(self, kActiveTokenKey);
        NSNumber *savedCounter = objc_getAssociatedObject(self, kTokenCounterKey);
        BOOL isPlaying = YES;
        @try {
            isPlaying = [[self valueForKey:@"isPlaying"] boolValue];
        } @catch (NSException *e) {}

        if (!isPlaying || !activeToken || [activeToken unsignedLongLongValue] != [savedCounter unsignedLongLongValue]) {
            NSLog(@"[EasyDict-Patch] Discarding outdated async audio URL for: %@", text);
            return;
        }

        // Notify other audio player instances to stop
        [[NSNotificationCenter defaultCenter] postNotificationName:kAudioDidStartNotification object:self];

        // Call original method
        ((void (*)(id, SEL, id, id, id, id, id, BOOL))objc_msgSend)(
            self, @selector(patched_playTextAudio:language:accent:audioURL:designatedService:forceURL:),
            text, language, accent, audioURL, designatedService, forceURL);
    }
}

- (void)patched_stop {
    // Invalidate active token for this player
    objc_setAssociatedObject(self, kActiveTokenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Call original stop
    ((void (*)(id, SEL))objc_msgSend)(self, @selector(patched_stop));
}

- (void)handlePatchOtherPlayerStarted:(NSNotification *)note {
    if (note.object != self) {
        if ([self respondsToSelector:@selector(stop)]) {
            [self performSelector:@selector(stop)];
        }
    }
}

@end

// MARK: - Constructor Initialization

__attribute__((constructor))
static void InitEasyDictPatch(void) {
    @autoreleasepool {
        NSLog(@"[EasyDict-Patch] Initializing auto-pronounce enhancements...");

        // 1. Swizzle EZBaseQueryViewController
        Class baseVCClass = NSClassFromString(@"EZBaseQueryViewController");
        if (baseVCClass) {
            SwizzleInstanceMethod(baseVCClass,
                                  @selector(autoPlayEnglishWordAudio),
                                  @selector(patched_autoPlayEnglishWordAudio));
            SwizzleInstanceMethod(baseVCClass,
                                  @selector(startQueryText:actionType:),
                                  @selector(patched_startQueryText:actionType:));
            SwizzleInstanceMethod(baseVCClass,
                                  @selector(queryCurrentModel),
                                  @selector(patched_queryCurrentModel));
        } else {
            NSLog(@"[EasyDict-Patch] Error: EZBaseQueryViewController class not found!");
        }

        // 2. Swizzle EZAudioPlayer
        Class audioPlayerClass = NSClassFromString(@"EZAudioPlayer");
        if (audioPlayerClass) {
            SwizzleInstanceMethod(audioPlayerClass,
                                  @selector(playTextAudio:language:accent:audioURL:designatedService:forceURL:),
                                  @selector(patched_playTextAudio:language:accent:audioURL:designatedService:forceURL:));
            SwizzleInstanceMethod(audioPlayerClass,
                                  @selector(stop),
                                  @selector(patched_stop));

            // Register notification listener on AudioPlayer init
            Method origInit = class_getInstanceMethod(audioPlayerClass, @selector(init));
            if (origInit) {
                typedef id (*InitFunc)(id, SEL);
                static InitFunc origInitImp = NULL;
                origInitImp = (InitFunc)method_getImplementation(origInit);
                id (^swizzledInitBlock)(id) = ^id(id selfInstance) {
                    selfInstance = origInitImp(selfInstance, @selector(init));
                    if (selfInstance) {
                        [[NSNotificationCenter defaultCenter] addObserver:selfInstance
                                                                 selector:@selector(handlePatchOtherPlayerStarted:)
                                                                     name:kAudioDidStartNotification
                                                                   object:nil];
                    }
                    return selfInstance;
                };
                method_setImplementation(origInit, imp_implementationWithBlock(swizzledInitBlock));
            }
        } else {
            NSLog(@"[EasyDict-Patch] Error: EZAudioPlayer class not found!");
        }

        NSLog(@"[EasyDict-Patch] Patch initialization finished successfully.");
    }
}
