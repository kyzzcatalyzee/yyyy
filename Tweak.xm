// DepthWall by zilvyn - lock screen depth effect (subject cut-out above the clock)
// Put your wallpaper at /var/mobile/Library/DepthWall/wallpaper.png then respring.
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>

#define DW_DIR   @"/var/mobile/Library/DepthWall"
#define DW_SRC   DW_DIR @"/wallpaper.png"
#define DW_CUT   DW_DIR @"/cutout.png"
#define DW_LOG   DW_DIR @"/log.txt"
#define DW_TAG   0xD37A

@interface CSProminentTimeView : UIView @end

static UIImage *gCutout;
static BOOL gBuilding;
static NSHashTable<UIImageView *> *gViews;

static void DWLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1,2);
static void DWLog(NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:a];
    va_end(a);
    NSString *line = [NSString stringWithFormat:@"%@\n", s];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:DW_LOG];
    if (!h) {
        [[NSFileManager defaultManager] createDirectoryAtPath:DW_DIR withIntermediateDirectories:YES attributes:nil error:nil];
        [line writeToFile:DW_LOG atomically:NO encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [h seekToEndOfFile];
    [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}

static NSDate *DWMod(NSString *p) {
    return [[[NSFileManager defaultManager] attributesOfItemAtPath:p error:nil] fileModificationDate];
}

static UIImage *DWBuildCutout(void) {
    UIImage *raw = [UIImage imageWithContentsOfFile:DW_SRC];
    if (!raw) { DWLog(@"no wallpaper at %@", DW_SRC); return nil; }

    // normalize orientation, cap size to keep memory low
    CGFloat maxSide = 1600, sc = MIN(1.0, maxSide / MAX(raw.size.width, raw.size.height));
    CGSize sz = CGSizeMake(floor(raw.size.width * sc), floor(raw.size.height * sc));
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat defaultFormat];
    f.scale = 1; f.opaque = YES;
    UIImage *norm = [[[UIGraphicsImageRenderer alloc] initWithSize:sz format:f]
        imageWithActions:^(UIGraphicsImageRendererContext *c) { [raw drawInRect:CGRectMake(0, 0, sz.width, sz.height)]; }];

    CIImage *ci = [[CIImage alloc] initWithCGImage:norm.CGImage];
    VNGeneratePersonSegmentationRequest *req = [[VNGeneratePersonSegmentationRequest alloc] init];
    req.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelAccurate;
    req.outputPixelFormat = kCVPixelFormatType_OneComponent8;
    NSError *err = nil;
    VNImageRequestHandler *h = [[VNImageRequestHandler alloc] initWithCIImage:ci options:@{}];
    if (![h performRequests:@[req] error:&err]) { DWLog(@"vision failed: %@", err); return nil; }
    VNPixelBufferObservation *obs = (VNPixelBufferObservation *)req.results.firstObject;
    if (!obs) { DWLog(@"no person found"); return nil; }

    CIImage *mask = [CIImage imageWithCVPixelBuffer:obs.pixelBuffer];
    mask = [mask imageByApplyingTransform:CGAffineTransformMakeScale(ci.extent.size.width / mask.extent.size.width,
                                                                     ci.extent.size.height / mask.extent.size.height)];
    CIFilter *blend = [CIFilter filterWithName:@"CIBlendWithMask"];
    [blend setValue:ci forKey:kCIInputImageKey];
    [blend setValue:[CIImage emptyImage] forKey:kCIInputBackgroundImageKey];
    [blend setValue:mask forKey:kCIInputMaskImageKey];
    CIContext *ctx = [CIContext contextWithOptions:nil];
    CGImageRef cg = [ctx createCGImage:blend.outputImage fromRect:ci.extent];
    if (!cg) { DWLog(@"render failed"); return nil; }
    UIImage *out = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    [UIImagePNGRepresentation(out) writeToFile:DW_CUT atomically:YES];
    DWLog(@"cutout built %@", NSStringFromCGSize(out.size));
    return out;
}

static void DWApplyToViews(void) {
    for (UIImageView *v in gViews.allObjects) { v.image = gCutout; v.hidden = (gCutout == nil); }
}

static void DWEnsureCutout(void) {
    if (gCutout || gBuilding) return;
    NSDate *s = DWMod(DW_SRC), *c = DWMod(DW_CUT);
    if (c && s && [c compare:s] != NSOrderedAscending) {
        gCutout = [UIImage imageWithContentsOfFile:DW_CUT];
        if (gCutout) { DWLog(@"loaded cached cutout"); DWApplyToViews(); return; }
    }
    if (!s) return;
    gBuilding = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        UIImage *img = DWBuildCutout();
        dispatch_async(dispatch_get_main_queue(), ^{ gBuilding = NO; gCutout = img; DWApplyToViews(); });
    });
}

static void DWAttach(UIView *clock) {
    UIView *parent = clock.superview;
    if (!parent) return;
    if (!gViews) gViews = [NSHashTable weakObjectsHashTable];
    UIImageView *v = (UIImageView *)[parent viewWithTag:DW_TAG];
    if (!v) {
        v = [[UIImageView alloc] init];
        v.tag = DW_TAG;
        v.contentMode = UIViewContentModeScaleAspectFill;
        v.clipsToBounds = YES;
        v.userInteractionEnabled = NO;
        v.image = gCutout; v.hidden = (gCutout == nil);
        [parent addSubview:v];
        [gViews addObject:v];
        DWLog(@"attached to %@ frame=%@ clock=%@ parentWindow=%@", NSStringFromClass(parent.class),
              NSStringFromCGRect(parent.bounds), NSStringFromCGRect(clock.frame), NSStringFromClass(parent.window.class));
    }
    v.frame = parent.bounds;
    v.layer.zPosition = clock.layer.zPosition + 2.0;
    DWEnsureCutout();
}

%hook CSProminentTimeView
- (void)didMoveToWindow { %orig; if (self.window) DWAttach(self); }
- (void)layoutSubviews { %orig; if (self.window) DWAttach(self); }
%end
