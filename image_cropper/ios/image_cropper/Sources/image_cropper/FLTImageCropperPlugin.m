#import "./include/image_cropper/FLTImageCropperPlugin.h"
#import "TOCropViewController.h"
#import <UIKit/UIKit.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <Photos/Photos.h>

@interface FLTImageCropperPlugin() <TOCropViewControllerDelegate>
@end

@implementation FLTImageCropperPlugin {
    FlutterResult _result;
    NSDictionary *_arguments;
    float _compressQuality;
    NSString *_compressFormat;
}
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:@"plugins.hunghd.vn/image_cropper"
                                     binaryMessenger:[registrar messenger]];
    FLTImageCropperPlugin* instance = [[FLTImageCropperPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"cropImage" isEqualToString:call.method]) {
        _result = result;
        _arguments = call.arguments;
        [self validateAspectRatioConstraints:call.arguments];
        NSString *sourcePath = call.arguments[@"source_path"];
        NSNumber *ratioX = call.arguments[@"ratio_x"];
        NSNumber *ratioY = call.arguments[@"ratio_y"];
        NSString *cropStyle = call.arguments[@"ios.crop_style"];
        NSArray *aspectRatioPresets = call.arguments[@"ios.aspect_ratio_presets"];
        NSNumber *compressQuality = call.arguments[@"compress_quality"];
        NSString *compressFormat = call.arguments[@"compress_format"];
        BOOL embedInNavigationController = call.arguments[@"ios.embed_in_navigation_controller"];

        UIImage *image = [UIImage imageWithContentsOfFile:sourcePath];
        TOCropViewController *cropViewController;

        if ([@"circle" isEqualToString:cropStyle]) {
            cropViewController = [[TOCropViewController alloc] initWithCroppingStyle:TOCropViewCroppingStyleCircular image:image];
        } else {
            cropViewController = [[TOCropViewController alloc] initWithImage:image];
        }

        cropViewController.delegate = self;

        if (compressQuality && [compressQuality isKindOfClass:[NSNumber class]]) {
            _compressQuality = compressQuality.intValue * 1.0f / 100;
        } else {
            _compressQuality = 0.9f;
        }
        if (compressFormat && [compressFormat isKindOfClass:[NSString class]]) {
            _compressFormat = compressFormat;
        } else {
            _compressFormat = @"jpg";
        }

        NSMutableArray *allowedAspectRatios = [NSMutableArray new];
        NSString* customAspectRatioName;
        NSDictionary* customAspectRatioData;
        for (NSDictionary *preset in aspectRatioPresets) {
            if (preset) {
                TOCropViewControllerAspectRatioPreset presetValue = [self parseAspectRatioPresetFromDict:preset];
                if (presetValue == TOCropViewControllerAspectRatioPresetCustom) {
                    customAspectRatioName = preset[@"name"];
                    customAspectRatioData = preset[@"data"];
                } else {
                    [allowedAspectRatios addObject:@(presetValue)];
                }
            }
        }
        if (customAspectRatioName && customAspectRatioData) {
            NSNumber* ratioX = customAspectRatioData[@"ratio_x"];
            NSNumber* ratioY = customAspectRatioData[@"ratio_y"];
            if (ratioX && ratioY) {
                cropViewController.customAspectRatioName = customAspectRatioName;
                cropViewController.customAspectRatio = CGSizeMake([ratioX floatValue], [ratioY floatValue]);
            }
        }
        cropViewController.allowedAspectRatios = allowedAspectRatios;

        [self setupUiCustomizedOptions:call.arguments forViewController:cropViewController];

        if (ratioX != (id)[NSNull null] && ratioY != (id)[NSNull null]) {
            cropViewController.customAspectRatio = CGSizeMake([ratioX floatValue], [ratioY floatValue]);
            cropViewController.resetAspectRatioEnabled = NO;
            cropViewController.aspectRatioPickerButtonHidden = YES;
            cropViewController.aspectRatioLockDimensionSwapEnabled = YES;
            cropViewController.aspectRatioLockEnabled = YES;
        }

        // ========== ADD THIS (Mirrors Android Fix) ==========
        NSNumber *maxWidth = call.arguments[@"max_width"];
        NSNumber *maxHeight = call.arguments[@"max_height"];

        if (maxWidth != (id)[NSNull null] && maxHeight != (id)[NSNull null]) {
            CGFloat aspectRatioValue = [ratioX floatValue] / [ratioY floatValue];
            CGFloat maxSizeRatio = [maxWidth floatValue] / [maxHeight floatValue];
            CGFloat ratioDifference = fabs(aspectRatioValue - maxSizeRatio);

            if (ratioDifference > aspectRatioValue * 0.01) {
                NSLog(@"⚠️ [ImageCropper] Aspect ratio mismatch detected!");
                NSLog(@"   Target ratio: %.3f (%.0f:%.0f)",
                      aspectRatioValue, [ratioX floatValue], [ratioY floatValue]);
                NSLog(@"   Max size ratio: %.3f (%.0fx%.0f)",
                      maxSizeRatio, [maxWidth floatValue], [maxHeight floatValue]);
                NSLog(@"   Warning: Output may be stretched!");
            }
        }
        // ========== END NEW CODE ==========

        UIWindow *window = [UIApplication sharedApplication].delegate.window;
        if (!window) {
            if (@available(iOS 13.0, *)) {
                for (UIWindowScene* scene in [UIApplication sharedApplication].connectedScenes) {
                    if (scene.activationState == UISceneActivationStateForegroundActive) {
                        for (UIWindow *w in scene.windows) {
                            if (w.isKeyWindow) {
                                window = w;
                                break;
                            }
                        }
                    }
                }
            } else {
                return;
            }
        }

        UIViewController *topController = window.rootViewController;
        while (topController.presentedViewController && !topController.presentedViewController.isBeingDismissed) {
            topController = topController.presentedViewController;
        }

        if (embedInNavigationController) {
            UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController: cropViewController];
            navigationController.modalTransitionStyle = cropViewController.modalTransitionStyle;
            navigationController.modalPresentationStyle = cropViewController.modalPresentationStyle;
            navigationController.transitioningDelegate = cropViewController.transitioningDelegate;
            [topController presentViewController:navigationController animated:YES completion:nil];
        } else {
            [topController presentViewController:cropViewController animated:YES completion:nil];
        }
  } else {
      result(FlutterMethodNotImplemented);
  }
}

- (void)setupUiCustomizedOptions:(id)options forViewController:(TOCropViewController*)controller {
    NSNumber *minimumAspectRatio = options[@"ios.minimum_aspect_ratio"];
    NSNumber *rectX = options[@"ios.rect_x"];
    NSNumber *rectY = options[@"ios.rect_y"];
    NSNumber *rectWidth = options[@"ios.rect_width"];
    NSNumber *rectHeight = options[@"ios.rect_height"];
    NSNumber *showActivitySheetOnDone = options[@"ios.show_activity_sheet_on_done"];
    NSNumber *showCancelConfirmationDialog = options[@"ios.show_cancel_confirmation_dialog"];
    NSNumber *rotateClockwiseButtonHidden = options[@"ios.rotate_clockwise_button_hidden"];
    NSNumber *hidesNavigationBar = options[@"ios.hides_navigation_bar"];
    NSNumber *rotateButtonHidden = options[@"ios.rotate_button_hidden"];
    NSNumber *resetButtonHidden = options[@"ios.reset_button_hidden"];
    NSNumber *aspectRatioPickerButtonHidden = options[@"ios.aspect_ratio_picker_button_hidden"];
    NSNumber *resetAspectRatioEnabled = options[@"ios.reset_aspect_ratio_enabled"];
    NSNumber *aspectRatioLockDimensionSwapEnabled = options[@"ios.aspect_ratio_lock_dimension_swap_enabled"];
    NSNumber *aspectRatioLockEnabled = options[@"ios.aspect_ratio_lock_enabled"];
    NSString *title = options[@"ios.title"];
    NSString *doneButtonTitle = options[@"ios.done_button_title"];
    NSString *cancelButtonTitle = options[@"ios.cancel_button_title"];

    if (minimumAspectRatio && [minimumAspectRatio isKindOfClass:[NSNumber class]]) {
        controller.minimumAspectRatio = minimumAspectRatio.floatValue;
    }
    if (rectX && [rectX isKindOfClass:[NSNumber class]]
        && rectY && [rectY isKindOfClass:[NSNumber class]]
        && rectWidth && [rectWidth isKindOfClass:[NSNumber class]]
        && rectHeight && [rectHeight isKindOfClass:[NSNumber class]]) {
        controller.imageCropFrame = CGRectMake(rectX.floatValue, rectY.floatValue, rectWidth.floatValue, rectHeight.floatValue);
    }
    if (showActivitySheetOnDone && [showActivitySheetOnDone isKindOfClass:[NSNumber class]]) {
        controller.showActivitySheetOnDone = showActivitySheetOnDone.boolValue;
    }
    if (showCancelConfirmationDialog && [showCancelConfirmationDialog isKindOfClass:[NSNumber class]]) {
        controller.showCancelConfirmationDialog = showCancelConfirmationDialog.boolValue;
    }
    if (rotateClockwiseButtonHidden && [rotateClockwiseButtonHidden isKindOfClass:[NSNumber class]]) {
        controller.rotateClockwiseButtonHidden = rotateClockwiseButtonHidden.boolValue;
    }
    if (hidesNavigationBar && [hidesNavigationBar isKindOfClass:[NSNumber class]]) {
        controller.hidesNavigationBar = hidesNavigationBar.boolValue;
    }
    if (rotateButtonHidden && [rotateButtonHidden isKindOfClass:[NSNumber class]]) {
        controller.rotateButtonsHidden = rotateButtonHidden.boolValue;
    }
    if (resetButtonHidden && [resetButtonHidden isKindOfClass:[NSNumber class]]) {
        controller.resetButtonHidden = resetButtonHidden.boolValue;
    }
    if (aspectRatioPickerButtonHidden && [aspectRatioPickerButtonHidden isKindOfClass:[NSNumber class]]) {
        controller.aspectRatioPickerButtonHidden = aspectRatioPickerButtonHidden.boolValue;
    }
    if (resetAspectRatioEnabled && [resetAspectRatioEnabled isKindOfClass:[NSNumber class]]) {
        controller.resetAspectRatioEnabled = resetAspectRatioEnabled.boolValue;
    }
    if (aspectRatioLockDimensionSwapEnabled && [aspectRatioLockDimensionSwapEnabled isKindOfClass:[NSNumber class]]) {
        controller.aspectRatioLockDimensionSwapEnabled = aspectRatioLockDimensionSwapEnabled.boolValue;
    }
    if (aspectRatioLockEnabled && [aspectRatioLockEnabled isKindOfClass:[NSNumber class]]) {
        controller.aspectRatioLockEnabled = aspectRatioLockEnabled.boolValue;
    }
    if (title && [title isKindOfClass:[NSString class]]) {
        controller.title = title;
    }
    if (doneButtonTitle && [doneButtonTitle isKindOfClass:[NSString class]]) {
        controller.doneButtonTitle = doneButtonTitle;
    }
    if (cancelButtonTitle && [cancelButtonTitle isKindOfClass:[NSString class]]) {
        controller.cancelButtonTitle = cancelButtonTitle;
    }
}

- (TOCropViewControllerAspectRatioPreset)parseAspectRatioPresetFromDict:(NSDictionary*)dict {
    NSString* name = dict[@"name"];
    if ([@"square" isEqualToString:name]) {
        return TOCropViewControllerAspectRatioPresetSquare;
    } else if ([@"original" isEqualToString:name]) {
        return TOCropViewControllerAspectRatioPresetOriginal;
    } else if ([@"3x2" isEqualToString:name]) {
        return TOCropViewControllerAspectRatioPreset3x2;
    } else if ([@"4x3" isEqualToString:name]) {
        return TOCropViewControllerAspectRatioPreset4x3;
    } else if ([@"5x3" isEqualToString:name]) {
        return TOCropViewControllerAspectRatioPreset5x3;
    } else if ([@"5x4" isEqualToString:name]) {
        return TOCropViewControllerAspectRatioPreset5x4;
    } else if ([@"7x5" isEqualToString:name]) {
        return TOCropViewControllerAspectRatioPreset7x5;
    } else if ([@"16x9" isEqualToString:name]) {
        return TOCropViewControllerAspectRatioPreset16x9;
    } else {
        return TOCropViewControllerAspectRatioPresetCustom;
    }
}

# pragma TOCropViewControllerDelegate

- (void)cropViewController:(TOCropViewController *)cropViewController
            didCropToImage:(UIImage *)image
                  withRect:(CGRect)cropRect
                     angle:(NSInteger)angle {
    image = [self normalizedImage:image];

    // ========== ADD VALIDATION (Like Android) ==========
    NSLog(@"========== [ImageCropper] Crop Result ==========");
    NSLog(@"Initial: %.0fx%.0f (AR: %.3f)",
          image.size.width, image.size.height,
          image.size.width / image.size.height);

    CGFloat originalAspectRatio = image.size.width / image.size.height;
    // ========== END INITIAL LOG ==========

    NSNumber *maxWidth = [_arguments objectForKey:@"max_width"];
    NSNumber *maxHeight = [_arguments objectForKey:@"max_height"];

    if (maxWidth != (id)[NSNull null] && maxHeight != (id)[NSNull null]) {
        image = [self scaledImage:image maxWidth:maxWidth maxHeight:maxHeight];

        // ========== VALIDATE OUTPUT (Like Android) ==========
        CGFloat scaledAspectRatio = image.size.width / image.size.height;
        CGFloat aspectRatioDiff = fabs(scaledAspectRatio - originalAspectRatio);

        if (aspectRatioDiff > originalAspectRatio * 0.01) {
            NSLog(@"❌ [ImageCropper] ASPECT RATIO VIOLATION!");
            NSLog(@"   Original AR: %.3f", originalAspectRatio);
            NSLog(@"   Scaled AR: %.3f", scaledAspectRatio);
        } else {
            NSLog(@"✅ [ImageCropper] Aspect ratio preserved");
        }
        NSLog(@"================================================");
        // ========== END VALIDATION ==========
    }

    NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString];

    NSData *data;
    NSString *tmpFile;

    if ([@"png" isEqualToString:_compressFormat]) {
        data = UIImagePNGRepresentation(image);
        tmpFile = [NSString stringWithFormat:@"image_cropper_%@.png", guid];
    } else {
        data = UIImageJPEGRepresentation(image, _compressQuality);
        tmpFile = [NSString stringWithFormat:@"image_cropper_%@.jpg", guid];
    }

    NSString *tmpDirectory = NSTemporaryDirectory();
    NSString *tmpPath = [tmpDirectory stringByAppendingPathComponent:tmpFile];

    if (_result) {
        if ([[NSFileManager defaultManager] createFileAtPath:tmpPath contents:data attributes:nil]) {
            _result(tmpPath);
        } else {
            _result([FlutterError errorWithCode:@"create_error"
                                        message:@"Temporary file could not be created"
                                        details:nil]);
        }

        [cropViewController dismissViewControllerAnimated:YES completion:nil];

        _result = nil;
        _arguments = nil;
    }
}

- (void)cropViewController:(TOCropViewController *)cropViewController didFinishCancelled:(BOOL)cancelled {
    [cropViewController dismissViewControllerAnimated:YES completion:nil];
    _result(nil);

    _result = nil;
    _arguments = nil;
}

// The way we save images to the tmp dir currently throws away all EXIF data
// (including the orientation of the image). That means, pics taken in portrait
// will not be orientated correctly as is. To avoid that, we rotate the actual
// image data.
// TODO(goderbauer): investigate how to preserve EXIF data.
- (UIImage *)normalizedImage:(UIImage *)image {
    if (image.imageOrientation == UIImageOrientationUp) return image;

    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    [image drawInRect:(CGRect){0, 0, image.size}];
    UIImage *normalizedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return normalizedImage;
}

- (UIImage *)scaledImage:(UIImage *)image
                maxWidth:(NSNumber *)maxWidth
               maxHeight:(NSNumber *)maxHeight {
    CGFloat originalWidth = image.size.width;
    CGFloat originalHeight = image.size.height;
    CGFloat originalAspectRatio = originalWidth / originalHeight;

    BOOL hasMaxWidth = maxWidth != (id)[NSNull null];
    BOOL hasMaxHeight = maxHeight != (id)[NSNull null];

    if (!hasMaxWidth && !hasMaxHeight) {
        return image;
    }

    CGFloat targetWidth = originalWidth;
    CGFloat targetHeight = originalHeight;

    // ========== SAME LOGIC AS ANDROID boxFitCover ==========
    if (hasMaxWidth && hasMaxHeight) {
        CGFloat maxW = [maxWidth doubleValue];
        CGFloat maxH = [maxHeight doubleValue];

        CGFloat scaleX = maxW / originalWidth;
        CGFloat scaleY = maxH / originalHeight;
        CGFloat scale = MIN(MIN(scaleX, scaleY), 1.0);  // BoxFit.contain

        targetWidth = round(originalWidth * scale);
        targetHeight = round(originalHeight * scale);

    } else if (hasMaxWidth) {
        CGFloat maxW = [maxWidth doubleValue];
        if (originalWidth > maxW) {
            targetWidth = maxW;
            targetHeight = round(maxW / originalAspectRatio);
        }
    } else {
        CGFloat maxH = [maxHeight doubleValue];
        if (originalHeight > maxH) {
            targetHeight = maxH;
            targetWidth = round(maxH * originalAspectRatio);
        }
    }

    // ========== VALIDATE LIKE ANDROID ==========
    CGFloat targetAspectRatio = targetWidth / targetHeight;
    CGFloat aspectRatioDiff = fabs(targetAspectRatio - originalAspectRatio);

    if (aspectRatioDiff > originalAspectRatio * 0.01) {
        NSLog(@"⚠️ [ImageCropper] Correcting aspect ratio violation");

        if (targetAspectRatio > originalAspectRatio) {
            targetWidth = round(targetHeight * originalAspectRatio);
        } else {
            targetHeight = round(targetWidth / originalAspectRatio);
        }
    }
    // ========== END VALIDATION ==========

    if (targetWidth >= originalWidth && targetHeight >= originalHeight) {
        return image;
    }

    NSLog(@"[ImageCropper] Scaling: %.0fx%.0f → %.0fx%.0f",
          originalWidth, originalHeight, targetWidth, targetHeight);

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(targetWidth, targetHeight), NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, targetWidth, targetHeight)];
    UIImage *scaledImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return scaledImage;
}

- (void)validateAspectRatioConstraints:(NSDictionary*)arguments {
    NSNumber *ratioX = arguments[@"ratio_x"];
    NSNumber *ratioY = arguments[@"ratio_y"];
    NSNumber *maxWidth = arguments[@"max_width"];
    NSNumber *maxHeight = arguments[@"max_height"];

    if (ratioX != (id)[NSNull null] && ratioY != (id)[NSNull null] &&
        maxWidth != (id)[NSNull null] && maxHeight != (id)[NSNull null]) {

        CGFloat targetAR = [ratioX floatValue] / [ratioY floatValue];
        CGFloat maxSizeAR = [maxWidth floatValue] / [maxHeight floatValue];
        CGFloat difference = fabs(targetAR - maxSizeAR) / targetAR * 100;

        if (difference > 1.0) {
            NSLog(@"⚠️ [ImageCropper] Aspect ratio mismatch: %.2f%%", difference);
            NSLog(@"   Target: %.3f, Max size: %.3f", targetAR, maxSizeAR);
        }
    }
}

@end
