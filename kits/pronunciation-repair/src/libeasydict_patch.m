#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static const char *kTokenCounterKey = "kTokenCounterKey";
static const char *kActiveTokenKey = "kActiveTokenKey";
static NSString *const kAudioDidStartNotification = @"kEasyDictPatchAudioDidStartNotification";
static char kQueryGenerationKey;
static char kSpokenGenerationKey;
static char kStartingQueryKey;
static char kPreservingSpeechKey;
static char kLocalHoverMonitorKey;
static char kGlobalHoverMonitorKey;
static char kPhoneticRequestKey;

// MARK: - Method Swizzling Helper

static void SwizzleInstanceMethod(Class cls, SEL origSel, SEL newSel) {
    Method origMethod = class_getInstanceMethod(cls, origSel);
    Method newMethod = class_getInstanceMethod(cls, newSel);
    if (!origMethod || !newMethod) {
        NSLog(@"[EasyDict-Patch] Failed to find methods for swizzling: %s / %s on %@",
              sel_getName(origSel), sel_getName(newSel), cls);
        return;
    }
    // Copy inherited category implementations onto the target class before
    // exchanging them, so NSObject itself is never changed by this patch.
    class_addMethod(cls, newSel, method_getImplementation(newMethod), method_getTypeEncoding(newMethod));
    newMethod = class_getInstanceMethod(cls, newSel);
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

- (void)easydive_startImmediateSpeech {
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

    NSNumber *generation = objc_getAssociatedObject(self, &kQueryGenerationKey) ?: @0;
    if ([generation isEqual:objc_getAssociatedObject(self, &kSpokenGenerationKey)]) {
        return;
    }
    objc_setAssociatedObject(self, &kSpokenGenerationKey, generation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Stop any existing playing audio first to prevent overlapping
    if ([self respondsToSelector:@selector(stopPlayingQueryText)]) {
        [self stopPlayingQueryText];
    }

    // Detect locally, but honor the user's selected TTS provider for playback.
    id player = [self valueForKey:@"audioPlayer"];
    id appleService = [player valueForKey:@"appleService"];
    SEL detectSelector = NSSelectorFromString(@"detectTextSync:");
    SEL speakSelector = NSSelectorFromString(@"playTextAudio:language:accent:audioURL:designatedService:");
    if ([appleService respondsToSelector:detectSelector] && [player respondsToSelector:speakSelector]) {
        id model = [self valueForKey:@"queryModel"];
        id language = [model valueForKey:@"queryFromLanguage"];
        if (![[model valueForKey:@"hasUserSourceLanguage"] boolValue]) {
            language = ((id (*)(id, SEL, id))objc_msgSend)(appleService, detectSelector, text);
        }
        id service = [self valueForKey:@"defaultTTSService"];
        id config = [self valueForKey:@"config"];
        NSString *accent = [[config valueForKey:@"pronunciation"] integerValue] == 1 ? @"uk" : @"us";
        ((void (*)(id, SEL, id, id, id, id, id))objc_msgSend)(player, speakSelector, text, language, accent, nil, service);
        NSLog(@"[EasyDive-Hover] configured TTS requested: %@, length=%lu", [service valueForKey:@"serviceType"], (unsigned long)text.length);
    } else {
        objc_setAssociatedObject(self, &kSpokenGenerationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSLog(@"[EasyDive-Hover] configured TTS API unavailable");
    }
}

- (void)patched_autoPlayEnglishWordAudio {
    [self easydive_startImmediateSpeech];
}

- (void)patched_autoPlayAudio {
    [self easydive_startImmediateSpeech];
}

- (void)patched_startQueryText:(NSString *)text actionType:(id)actionType {
    if ([[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length] == 0) {
        return;
    }
    NSUInteger generation = [objc_getAssociatedObject(self, &kQueryGenerationKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(self, &kQueryGenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([self respondsToSelector:@selector(stopPlayingQueryText)]) {
        [self stopPlayingQueryText];
    }
    objc_setAssociatedObject(self, &kStartingQueryKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        ((void (*)(id, SEL, id, id))objc_msgSend)(self, @selector(patched_startQueryText:actionType:), text, actionType);
    } @finally {
        objc_setAssociatedObject(self, &kStartingQueryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)patched_closeAllResultView:(void (^)(void))completion {
    BOOL starting = [objc_getAssociatedObject(self, &kStartingQueryKey) boolValue];
    if (!starting) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(patched_closeAllResultView:), completion);
        return;
    }
    NSNumber *generation = objc_getAssociatedObject(self, &kQueryGenerationKey);
    NSString *text = [[self valueForKey:@"queryText"] copy];
    [self easydive_startImmediateSpeech];
    void (^guardedCompletion)(void) = ^{
        if (![generation isEqual:objc_getAssociatedObject(self, &kQueryGenerationKey)] ||
            ![text isEqual:[self valueForKey:@"queryText"]]) {
            return;
        }
        objc_setAssociatedObject(self, &kPreservingSpeechKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @try {
            if (completion) { completion(); }
        } @finally {
            objc_setAssociatedObject(self, &kPreservingSpeechKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    };
    ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(patched_closeAllResultView:), guardedCompletion);
}

- (void)patched_stopPlayingQueryText {
    if (![objc_getAssociatedObject(self, &kPreservingSpeechKey) boolValue]) {
        ((void (*)(id, SEL))objc_msgSend)(self, @selector(patched_stopPlayingQueryText));
    }
}

- (void)patched_queryCurrentModel {
    BOOL preserving = [objc_getAssociatedObject(self, &kPreservingSpeechKey) boolValue];
    if (!preserving) {
        [self stopPlayingQueryText];
        NSUInteger generation = [objc_getAssociatedObject(self, &kQueryGenerationKey) unsignedIntegerValue] + 1;
        objc_setAssociatedObject(self, &kQueryGenerationKey, @(generation), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // The original method starts language detection asynchronously. Speak on
    // this turn, and suppress its later autoplay for the same query generation.
    ((void (*)(id, SEL))objc_msgSend)(self, @selector(patched_queryCurrentModel));
    [self easydive_startImmediateSpeech];
}

@end

// MARK: - Selection badge hover recovery

static void StopHoverMonitoring(NSWindow *window) {
    for (NSValue *keyValue in @[[NSValue valueWithPointer:&kLocalHoverMonitorKey],
                                [NSValue valueWithPointer:&kGlobalHoverMonitorKey]]) {
        const void *key = keyValue.pointerValue;
        id monitor = objc_getAssociatedObject(window, key);
        if (monitor) {
            [NSEvent removeMonitor:monitor];
            objc_setAssociatedObject(window, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static void ActivateHoverIfNeeded(NSWindow *window) {
    if (!window.isVisible || !NSPointInRect(NSEvent.mouseLocation, window.frame)) {
        return;
    }
    id button = [window valueForKey:@"popButton"];
    void (^mouseEnter)(id) = [button valueForKey:@"mouseEnterBlock"];
    if ([[button valueForKey:@"enabled"] boolValue] && mouseEnter) {
        mouseEnter(button);
    }
}

static void InstallHoverRecovery(void) {
    Class windowClass = NSClassFromString(@"EZPopButtonWindow");
    Class managerClass = NSClassFromString(@"EZWindowManager");
    if (!windowClass || !managerClass) {
        NSLog(@"[EasyDive-Hover] selection classes unavailable");
        return;
    }

    SEL showSelector = @selector(orderFrontRegardless);
    Method showMethod = class_getInstanceMethod(windowClass, showSelector);
    IMP originalShow = method_getImplementation(showMethod);
    IMP show = imp_implementationWithBlock(^(NSWindow *window) {
        ((void (*)(id, SEL))originalShow)(window, showSelector);
        StopHoverMonitoring(window);
        window.acceptsMouseMovedEvents = YES;
        __weak NSWindow *weakWindow = window;
        id localMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskMouseMoved handler:^NSEvent *(NSEvent *event) {
            ActivateHoverIfNeeded(weakWindow);
            return event;
        }];
        id globalMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskMouseMoved handler:^(NSEvent *event) {
            ActivateHoverIfNeeded(weakWindow);
        }];
        objc_setAssociatedObject(window, &kLocalHoverMonitorKey, localMonitor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(window, &kGlobalHoverMonitorKey, globalMonitor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        dispatch_async(dispatch_get_main_queue(), ^{ ActivateHoverIfNeeded(weakWindow); });
    });
    class_replaceMethod(windowClass, showSelector, show, method_getTypeEncoding(showMethod));

    SEL closeSelector = @selector(close);
    Method closeMethod = class_getInstanceMethod(windowClass, closeSelector);
    IMP originalClose = method_getImplementation(closeMethod);
    class_replaceMethod(windowClass, closeSelector, imp_implementationWithBlock(^(NSWindow *window) {
        StopHoverMonitoring(window);
        ((void (*)(id, SEL))originalClose)(window, closeSelector);
    }), method_getTypeEncoding(closeMethod));

    SEL outSelector = @selector(orderOut:);
    Method outMethod = class_getInstanceMethod(windowClass, outSelector);
    IMP originalOut = method_getImplementation(outMethod);
    class_replaceMethod(windowClass, outSelector, imp_implementationWithBlock(^(NSWindow *window, id sender) {
        StopHoverMonitoring(window);
        ((void (*)(id, SEL, id))originalOut)(window, outSelector, sender);
    }), method_getTypeEncoding(outMethod));

    SEL activateSelector = NSSelectorFromString(@"popButtonWindowClicked");
    Method activateMethod = class_getInstanceMethod(managerClass, activateSelector);
    IMP originalActivate = method_getImplementation(activateMethod);
    class_replaceMethod(managerClass, activateSelector, imp_implementationWithBlock(^(id manager) {
        NSWindow *window = [manager valueForKey:@"popButtonWindow"];
        if (!window.isVisible) {
            return;
        }
        NSLog(@"[EasyDive-Hover] selection badge activated once");
        ((void (*)(id, SEL))originalActivate)(manager, activateSelector);
    }), method_getTypeEncoding(activateMethod));
}

// MARK: - EZAudioPlayer Swizzling

@implementation NSObject (EZAudioPlayerPatch)

// Phonetic buttons supply an audio URL on the initial call. Mark only their
// synchronous entry, so a later network callback still uses cancellation checks.
- (void)patched_playWordPhonetic:(id)wordPhonetic designatedService:(id)designatedService {
    id previousRequest = objc_getAssociatedObject(self, &kPhoneticRequestKey);
    objc_setAssociatedObject(self, &kPhoneticRequestKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        ((void (*)(id, SEL, id, id))objc_msgSend)(
            self, @selector(patched_playWordPhonetic:designatedService:), wordPhonetic, designatedService);
    } @finally {
        objc_setAssociatedObject(self, &kPhoneticRequestKey, previousRequest, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)patched_speechSynthesizer:(id)sender didFinishSpeaking:(BOOL)finished {
    if (sender == [self valueForKey:@"synthesizer"]) {
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(self, @selector(patched_speechSynthesizer:didFinishSpeaking:), sender, finished);
    }
}

- (void)patched_playTextAudio:(NSString *)text
                     language:(id)language
                       accent:(id)accent
                     audioURL:(NSString *)audioURL
            designatedService:(id)designatedService
                     forceURL:(BOOL)forceURL {
    if (!text || text.length == 0) {
        return;
    }

    if (!audioURL.length || [objc_getAssociatedObject(self, &kPhoneticRequestKey) boolValue]) {
        // Initial TTS request or an explicit phonetic speaker click
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
            if (class_getInstanceMethod(baseVCClass, NSSelectorFromString(@"autoPlayAudio"))) {
                SwizzleInstanceMethod(baseVCClass,
                                      NSSelectorFromString(@"autoPlayAudio"),
                                      @selector(patched_autoPlayAudio));
            }
            SwizzleInstanceMethod(baseVCClass,
                                  @selector(startQueryText:actionType:),
                                  @selector(patched_startQueryText:actionType:));
            SwizzleInstanceMethod(baseVCClass,
                                  @selector(queryCurrentModel),
                                  @selector(patched_queryCurrentModel));
            SwizzleInstanceMethod(baseVCClass,
                                  NSSelectorFromString(@"closeAllResultView:"),
                                  @selector(patched_closeAllResultView:));
            SwizzleInstanceMethod(baseVCClass,
                                  @selector(stopPlayingQueryText),
                                  @selector(patched_stopPlayingQueryText));
        } else {
            NSLog(@"[EasyDict-Patch] Error: EZBaseQueryViewController class not found!");
        }

        // 2. Swizzle EZAudioPlayer
        Class audioPlayerClass = NSClassFromString(@"EZAudioPlayer");
        if (audioPlayerClass) {
            SwizzleInstanceMethod(audioPlayerClass,
                                  @selector(playWordPhonetic:designatedService:),
                                  @selector(patched_playWordPhonetic:designatedService:));
            SwizzleInstanceMethod(audioPlayerClass,
                                  @selector(playTextAudio:language:accent:audioURL:designatedService:forceURL:),
                                  @selector(patched_playTextAudio:language:accent:audioURL:designatedService:forceURL:));
            SwizzleInstanceMethod(audioPlayerClass,
                                  @selector(stop),
                                  @selector(patched_stop));
            SwizzleInstanceMethod(audioPlayerClass,
                                  @selector(speechSynthesizer:didFinishSpeaking:),
                                  @selector(patched_speechSynthesizer:didFinishSpeaking:));

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

        InstallHoverRecovery();
        NSLog(@"[EasyDive-Hover] immediate hover and speech patch initialized");
    }
}
