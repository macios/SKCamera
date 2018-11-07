//
//  SKCameraView.m
//  duoduo
//
//  Created by ac hu on 2017/11/20.
//  Copyright © 2017年 Locke. All rights reserved.
//

#import "SKCameraView.h"
#import <CoreMotion/CoreMotion.h>
#import <AVFoundation/AVFoundation.h>
#import "UIImage+SKImage.h"

#define SKTagSetAlert 10002
#define SKTagCompressAlert 10003
#define SKTagCross 1000
#define SKTagVertical 2000
#define SKNumCross 5
#define SKNumVertical 4

#define SKCameraViewScreenWidth [UIScreen mainScreen].bounds.size.width
#define SKCameraViewScreenHeight [UIScreen mainScreen].bounds.size.height

#define SKVIEW_W(VIEW) CGRectGetWidth(VIEW.frame)//视图宽
#define SKVIEW_H(VIEW) CGRectGetHeight(VIEW.frame)//视图高
#define SKVIEW_CenterX(VIEW) SKVIEW_W(VIEW)/2.0//视图中心x
#define SKVIEW_CenterY(VIEW) SKVIEW_H(VIEW)/2.0//视图中心y

#define SKMarginA 5.//间距
/** 前置或后置摄像头 */
typedef NS_ENUM(NSInteger, TakePicturePosition)
{
    TakePicturePositionBack = 0,
    TakePicturePositionFront
};

@interface SKCameraView()<UIGestureRecognizerDelegate>
//压缩比
@property (nonatomic,assign)float imageCompress;
//session：由他把输入输出结合在一起，并开始启动捕获设备（摄像头）
@property (nonatomic, strong) AVCaptureSession *session;
//AVCaptureDeviceInput 代表输入设备，他使用AVCaptureDevice 来初始化
@property(nonatomic, strong) AVCaptureDeviceInput *videoInput;
//当启动摄像头开始捕获输入
@property (nonatomic, strong) AVCaptureStillImageOutput *stillImageOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
//捕获设备，通常是前置摄像头，后置摄像头，麦克风（音频输入）
@property(nonatomic)AVCaptureDevice *device;
@property (nonatomic,strong)UIButton *takePicBtn;
@property (nonatomic,strong)UIButton *changeCameraBtn;
@property (nonatomic,assign) AVCaptureVideoOrientation deviceOrientation;
//是前置还是后置摄像头
@property (nonatomic,assign)TakePicturePosition position;
@property (nonatomic,strong) CMMotionManager *mgr;//加速器
@property (nonatomic,weak)UIView *cameraView;//相机录制视图
@property(nonatomic,assign)CGFloat beginGestureScale;//记录开始的缩放比例
@property(nonatomic,assign)CGFloat effectiveScale;//最后的缩放比例
@property (nonatomic,strong)UIView  *focusView;//聚焦视图
@property (nonatomic,strong)UIButton *flashButton;//闪光灯按钮
@property (nonatomic,strong)UIButton *netBtn;//网格按钮
@property (nonatomic,strong)UIButton *compressBtn;//压缩比按钮
@end


@implementation SKCameraView

+(instancetype)share{
    static SKCameraView *share = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        share = [[SKCameraView alloc] initOther];
    });
    return share;
}

-(instancetype)initOther{
    if (self = [super init]) {
        self.backgroundColor = [UIColor clearColor];
        self.imageCompress = 1.;
        [self creatView];
    }
    return self;
}

-(instancetype)init{
    @throw [NSException exceptionWithName:@"share" reason:@"单例" userInfo:nil];
    return nil;
}

-(void)creatView{
    void (^checkCamera)(void) = ^(){
        NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            //打开相机提示框
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"您未授权"
                                                            message:@"你没有摄像头\n请在设备的\"设置-隐私-相机\"中允许访问相机。"
                                                           delegate:self cancelButtonTitle:@"取消"
                                                  otherButtonTitles:@"设置",nil];
            alert.tag = SKTagSetAlert;
            [alert show];
        }
    };
    NSString *mediaType = AVMediaTypeVideo;
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:mediaType];
    if(authStatus == AVAuthorizationStatusRestricted || authStatus == AVAuthorizationStatusDenied){
        checkCamera();
        return;
    }
    _deviceOrientation = AVCaptureVideoOrientationPortrait;
    if (!self.isAuthorizedCamera || !self.isCameraAvailable) {
        NSLog(@"不能拍照");
        return;
    }
    
    [self creatCameraView];
    
    //检测是否可以用相机功能
    BOOL canCa = [self canUserCamear];
    if (canCa) {
        [self initialSession];
    }else{
        return;
    }
    
    self.effectiveScale = self.beginGestureScale = 1.0f;
    [self creatCMMotion];
    [self CMMotionStart];
    self.clipsToBounds = YES;
    self.frame = CGRectMake(SKCameraViewScreenWidth / 2.f, 0, SKCameraViewScreenWidth, SKCameraViewScreenHeight);
}


-(void)creatCameraView{
    // 设置相机捕捉视图界面
    UIView *cameraView = [[UIView alloc] init];
    cameraView.backgroundColor = [UIColor blackColor];
    cameraView.clipsToBounds = NO;
    [self addSubview:cameraView];
    self.cameraView = cameraView;
    
    for (int i = 0; i < SKNumCross; i ++) {
        UIView *view = [[UIView alloc]init];
        view.backgroundColor = [UIColor whiteColor];
        view.hidden = YES;
        [self.cameraView addSubview:view];
        view.tag = SKTagCross + i;
    }
    
    for (int i = 0; i < SKNumVertical; i ++) {
        UIView *view = [[UIView alloc]init];
        view.backgroundColor = [UIColor whiteColor];
        view.hidden = YES;
        view.tag = SKTagVertical + i;
        [self.cameraView addSubview:view];
    }
    
    //拍照按钮
    UIButton *takePicBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [takePicBtn setImage:[UIImage imageNamed:@"takePic_take"] forState:UIControlStateNormal];
    [takePicBtn addTarget:self action:@selector(takePic) forControlEvents:UIControlEventTouchUpInside];
    [cameraView addSubview:takePicBtn];
    self.takePicBtn = takePicBtn;
    
    //摄像头切换按钮
    self.changeCameraBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.changeCameraBtn setImage:[UIImage imageNamed:@"takePic_switch"] forState:UIControlStateNormal];
    [self.changeCameraBtn addTarget:self action:@selector(changeCamera) forControlEvents:UIControlEventTouchUpInside];
    [cameraView addSubview:self.changeCameraBtn];
    self.changeCameraBtn.hidden = YES;
    
    //闪光灯按钮
    _flashButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_flashButton setImage:[UIImage imageNamed:@"takepic_flashN"] forState:UIControlStateNormal];
    [_flashButton setImage:[UIImage imageNamed:@"takepic_flashH"] forState:UIControlStateSelected];
    [_flashButton addTarget:self action:@selector(FlashOn) forControlEvents:UIControlEventTouchUpInside];
    [self.cameraView addSubview:_flashButton];
    _flashButton.hidden = YES;
    
    //网格按钮
    _netBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_netBtn setImage:[UIImage imageNamed:@"takePic_netN"] forState:UIControlStateNormal];
    [_netBtn setImage:[UIImage imageNamed:@"takePic_netH"] forState:UIControlStateSelected];
    [_netBtn addTarget:self action:@selector(netBtnClcik) forControlEvents:UIControlEventTouchUpInside];
    [self.cameraView addSubview:_netBtn];
    
    //高清按钮
    _compressBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [_compressBtn setTitle:@"高清" forState:UIControlStateNormal];
    [_compressBtn setTitleColor:[UIColor colorWithRed:255 / 255.0 green:193 / 255.0 blue:0 alpha:1] forState:UIControlStateSelected];
    [_compressBtn setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
    _compressBtn.backgroundColor = [UIColor clearColor];
    [_compressBtn addTarget:self action:@selector(compressBtnClcik) forControlEvents:UIControlEventTouchUpInside];
    [self.cameraView addSubview:_compressBtn];
    _compressBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    
    //聚焦视图
    _focusView = [[UIView alloc]initWithFrame:CGRectMake(0, 0, 30, 30)];
    _focusView.layer.borderWidth = 1.0;
    _focusView.layer.borderColor =[UIColor greenColor].CGColor;
    _focusView.backgroundColor = [UIColor clearColor];
    [self.cameraView addSubview:_focusView];
    _focusView.hidden = YES;
    
    UIPinchGestureRecognizer *fousPinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchGesture:)];
    fousPinch.delegate = self;
    [self.cameraView addGestureRecognizer:fousPinch];
    
    //点击对焦手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(focusGesture:)];
    tapGesture.delegate = self;
    [self.cameraView addGestureRecognizer:tapGesture];
    
    //移动手势
    UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(wayPan:)];
    pan.delegate = self;
    [self addGestureRecognizer:pan];
}

-(void)setHidden:(BOOL)hidden{
    [super setHidden:hidden];
    if (hidden == NO) {
        [self focusAtPoint:CGPointMake(SKVIEW_CenterX(self.cameraView), SKVIEW_CenterY(self.cameraView))];
    }
}

#pragma mark 调焦
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if ( [gestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]] ) {
        self.beginGestureScale = self.effectiveScale;
    }
    return YES;
}

//缩放手势 用于调整焦距
- (void)handlePinchGesture:(UIPinchGestureRecognizer *)recognizer{
    BOOL allTouchesAreOnThePreviewLayer = YES;
    NSUInteger numTouches = [recognizer numberOfTouches], i;
    for ( i = 0; i < numTouches; ++i ) {
        CGPoint location = [recognizer locationOfTouch:i inView:self.cameraView];
        CGPoint convertedLocation = [self.previewLayer convertPoint:location fromLayer:self.previewLayer.superlayer];
        if ( ! [self.previewLayer containsPoint:convertedLocation] ) {
            allTouchesAreOnThePreviewLayer = NO;
            break;
        }
    }
    
    if ( allTouchesAreOnThePreviewLayer ) {
        self.effectiveScale = self.beginGestureScale * recognizer.scale;
        if (self.effectiveScale < 1.0){
            self.effectiveScale = 1.0;
        }
        
        CGFloat maxScaleAndCropFactor = [[self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo] videoMaxScaleAndCropFactor];
        
        if (self.effectiveScale > maxScaleAndCropFactor)
            self.effectiveScale = maxScaleAndCropFactor;
        
        [CATransaction begin];
        [CATransaction setAnimationDuration:.025];
        [self.previewLayer setAffineTransform:CGAffineTransformMakeScale(self.effectiveScale, self.effectiveScale)];
        [CATransaction commit];
        
    }
    
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        [self focusAtPoint:CGPointMake(SKVIEW_CenterX(self.cameraView), SKVIEW_CenterY(self.cameraView))];
    }
}

- (void)focusGesture:(UITapGestureRecognizer*)gesture{
    CGPoint point = [gesture locationInView:gesture.view];
    [self focusAtPoint:point];
}

- (void)focusAtPoint:(CGPoint)point{
    CGSize size = self.bounds.size;
    CGPoint focusPoint = CGPointMake( point.y /size.height ,1-point.x/size.width );
    NSError *error;
    if ([self.device lockForConfiguration:&error]) {
        
        if ([self.device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
            [self.device setFocusPointOfInterest:focusPoint];
            [self.device setFocusMode:AVCaptureFocusModeAutoFocus];
        }
        
        if ([self.device isExposureModeSupported:AVCaptureExposureModeAutoExpose ]) {
            [self.device setExposurePointOfInterest:focusPoint];
            [self.device setExposureMode:AVCaptureExposureModeAutoExpose];
        }
        
        [self.device unlockForConfiguration];
        _focusView.center = point;
        _focusView.hidden = NO;
        typeof(self) __weak weakSelf = self;
        [UIView animateWithDuration:0.3 animations:^{
            weakSelf.focusView.transform = CGAffineTransformMakeScale(1.25, 1.25);
        }completion:^(BOOL finished) {
            [UIView animateWithDuration:0.5 animations:^{
                weakSelf.focusView.transform = CGAffineTransformIdentity;
            } completion:^(BOOL finished) {
                weakSelf.focusView.hidden = YES;
            }];
        }];
    }
}

-(void)wayPan:(UIPanGestureRecognizer *)pan{
    CGPoint point=[pan translationInView:[UIApplication sharedApplication].keyWindow];
    
    self.effectiveScale = self.effectiveScale * (1 + point.x * 0.001);
    if (self.effectiveScale < 1.0){
        self.effectiveScale = 1.0;
    }
    
    CGFloat maxScaleAndCropFactor = [[self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo] videoMaxScaleAndCropFactor];
    if (self.effectiveScale > maxScaleAndCropFactor)
        self.effectiveScale = maxScaleAndCropFactor;
    
    [CATransaction begin];
    [CATransaction setAnimationDuration:.025];
    [self.previewLayer setAffineTransform:CGAffineTransformMakeScale(self.effectiveScale, self.effectiveScale)];
    [CATransaction commit];
    
    if (pan.state == UIGestureRecognizerStateEnded) {
        [self focusAtPoint:CGPointMake(SKVIEW_CenterX(self.cameraView), SKVIEW_CenterY(self.cameraView))];
    }
    
}

- (void)initialSession {
    // 开启后置摄像头了
    _position = TakePicturePositionBack;
    
    //使用AVMediaTypeVideo 指明self.device代表视频，默认使用后置摄像头进行初始化
    self.device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    //这个方法的执行我放在init方法里了
    self.session = [[AVCaptureSession alloc] init];
    self.videoInput = [[AVCaptureDeviceInput alloc] initWithDevice:[self backCamera] error:nil];
    //[self fronCamera]方法会返回一个AVCaptureDevice对象，因为我初始化时是采用前摄像头，所以这么写，具体的实现方法后面会介绍
    if (@available(iOS 9.0, *)) {
        [self.session setSessionPreset:AVCaptureSessionPreset3840x2160];
    } else {
        [self.session setSessionPreset:AVCaptureSessionPresetHigh];
    }//需要更加清晰的照片的话可以重新设置新值
    self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    NSDictionary * outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys:AVVideoCodecJPEG,AVVideoCodecKey, nil];
    //这是输出流的设置参数AVVideoCodecJPEG参数表示以JPEG的图片格式输出图片
    [self.stillImageOutput setOutputSettings:outputSettings];
    
    if ([self.session canAddInput:self.videoInput]) {
        [self.session addInput:self.videoInput];
    }
    
    if ([self.session canAddOutput:self.stillImageOutput]) {
        [self.session addOutput:self.stillImageOutput];
    }
    
    if (self.session) {
        [self.session startRunning];
    }
    
    [self setUpCameraLayer];
    
    if ([_device lockForConfiguration:nil]) {
        //自动闪光灯关
        if ([_device isFlashModeSupported:AVCaptureFlashModeOff]) {
            [_device setFlashMode:AVCaptureFlashModeOff];
        }
        
        //自动白平衡
        if ([_device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeAutoWhiteBalance]) {
            [_device setWhiteBalanceMode:AVCaptureWhiteBalanceModeAutoWhiteBalance];
        }
        
        //自动对焦
        if ([_device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
            [_device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
        }
        
        //自动曝光
        if ([_device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            [_device setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        }
        [_device unlockForConfiguration];
    }
}

-(void)creatCMMotion{
    _mgr = [CMMotionManager new];
}

-(void)CMMotionStart{
    if (_mgr) {
        if (_mgr.gyroAvailable == YES) {
            _mgr.accelerometerUpdateInterval = .2;
            _mgr.gyroUpdateInterval = .2;
            [_mgr startAccelerometerUpdatesToQueue:[NSOperationQueue currentQueue] withHandler:^(CMAccelerometerData  *accelerometerData, NSError *error) {
                if (!error) {
                    [self outputAccelertionData:accelerometerData.acceleration];
                }else{
                    NSLog(@"%@", error);
                }
            }];
        }
    }
}

-(void)CMMotionStop{
    if (_mgr) {
        [_mgr stopAccelerometerUpdates];
    }
}

- (void)setUpCameraLayer{
    if (self.previewLayer == nil) {
        self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
        [self.previewLayer setFrame:CGRectMake(0, 0, SKVIEW_W(_cameraView), SKVIEW_H(_cameraView))];
        [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
        [_cameraView.layer insertSublayer:self.previewLayer below:[[_cameraView.layer sublayers] objectAtIndex:0]];
    }
}

- (AVCaptureDevice *)backCamera {
    return [self cameraWithPosition:self.position == TakePicturePositionBack ? AVCaptureDevicePositionBack :AVCaptureDevicePositionFront];
}

- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for ( AVCaptureDevice *device in devices )
        if ( device.position == position ){
            _device = device;
            return device;
        }
    return nil;
}

#pragma mark 判断是否可以进行拍照
- (BOOL)isAuthorizedCamera
{
    NSString *mediaType = AVMediaTypeVideo;
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:mediaType];
    return !(authStatus == AVAuthorizationStatusDenied || authStatus == AVAuthorizationStatusRestricted);
}

-(BOOL)isCameraAvailable{
    NSArray *mediaTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
    BOOL isAvailable =  [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
    
    BOOL _isCameraAvailable = YES;
    if (!isAvailable || [mediaTypes count] <= 0) {
        _isCameraAvailable = NO;
    }
    return _isCameraAvailable ;
}

//检查相机权限
- (BOOL)canUserCamear{
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (authStatus == AVAuthorizationStatusDenied) {
        UIAlertView *alertView = [[UIAlertView alloc]initWithTitle:@"请打开相机权限" message:@"请在手机系统设置中更改" delegate:self cancelButtonTitle:@"确定" otherButtonTitles:@"取消", nil];
        alertView.tag = 100;
        [alertView show];
        return NO;
    }
    else{
        return YES;
    }
    return YES;
}

-(void)takePic{
    [self gainPic];
}

//获取单个摄像头照片
-(void)gainPic{
    _takePicBtn.enabled = NO;
    typeof(self) __weak weakSelf = self;
    AVCaptureConnection *videoConnection = nil;
    for (AVCaptureConnection *connection in self.stillImageOutput.connections) {
        for (AVCaptureInputPort *port in [connection inputPorts]) {
            if ([[port mediaType] isEqual:AVMediaTypeVideo] ) {
                videoConnection = connection;
                break;
            }
        }
        if (videoConnection) { break; }
    }
    if (!videoConnection) {
        NSLog(@"获取照片失败!");
        weakSelf.takePicBtn.enabled = YES;
        return;
    }
    
    [videoConnection setVideoOrientation:_deviceOrientation];
    [videoConnection setVideoScaleAndCropFactor:self.effectiveScale];
    
    
    [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:videoConnection completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
        if (imageDataSampleBuffer == NULL) {
            weakSelf.takePicBtn.enabled = YES;
            return;
        }
        NSData * imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
        
        UIImage *gainImage = [UIImage imageWithData:imageData];
        
        AVCaptureDevicePosition position = AVCaptureDevicePositionUnspecified; //判断是前置摄像头还是后置摄像头
        NSArray *inputs = weakSelf.session.inputs;
        
        for (AVCaptureDeviceInput *input in inputs) {
            AVCaptureDevice *device = input.device;
            if ([device hasMediaType:AVMediaTypeVideo]) {
                position = device.position;
            }
        }
        
        //截可视范围之内的图
        gainImage = [gainImage imageTailorSize:self.frame.size];
        gainImage = [gainImage fixOrientation];
        if (weakSelf.donePic) {
            weakSelf.donePic(gainImage,weakSelf.compressBtn.selected ? 1.0 : weakSelf.imageCompress);
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            weakSelf.takePicBtn.enabled = YES;
        });
        
    }];
}

#pragma mark 切换前后摄像头
- (void)changeCamera{
    NSUInteger cameraCount = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count];
    
    if (cameraCount > 1) {
        NSError *error;
        CATransition *animation = [CATransition animation];
        animation.duration = .5f;
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        animation.type = @"oglFlip";
        AVCaptureDevice *newCamera = nil;
        AVCaptureDeviceInput *newInput = nil;
        AVCaptureDevicePosition position = [[_videoInput device] position];
        if (position == AVCaptureDevicePositionFront){
            newCamera = [self cameraWithPosition:AVCaptureDevicePositionBack];
            animation.subtype = kCATransitionFromLeft;
        }
        else {
            newCamera = [self cameraWithPosition:AVCaptureDevicePositionFront];
            animation.subtype = kCATransitionFromRight;
        }
        
        newInput = [AVCaptureDeviceInput deviceInputWithDevice:newCamera error:nil];
        [self.previewLayer addAnimation:animation forKey:nil];
        if (newInput != nil) {
            [self.session beginConfiguration];
            [self.session removeInput:_videoInput];
            if ([self.session canAddInput:newInput]) {
                [self.session addInput:newInput];
                self.videoInput = newInput;
                
            } else {
                [self.session addInput:self.videoInput];
            }
            [self.session commitConfiguration];
        } else if (error) {
            NSLog(@"toggle carema failed, error = %@", error);
        }
    }
}

#pragma mark 拍照方向
- (void)outputAccelertionData:(CMAcceleration)acceleration{
    CGFloat xx = acceleration.x;
    CGFloat yy = acceleration.y;
    CGFloat zz = acceleration.z;
    
    CGFloat device_angle = M_PI / 2.0f - atan2(yy, xx);
    if (device_angle > M_PI){
        device_angle -= 2 * M_PI;
    }
    if ((zz < -.60f) || (zz > .60f)) {
        if ( (device_angle > -M_PI_4) && (device_angle < M_PI_4) ){
            if(_deviceOrientation != AVCaptureVideoOrientationPortraitUpsideDown){
                _deviceOrientation = AVCaptureVideoOrientationPortraitUpsideDown;//手机右放（眼对着屏幕）
            }
        }else if ((device_angle < -M_PI_4) && (device_angle > -3 * M_PI_4)){
            if(_deviceOrientation != AVCaptureVideoOrientationLandscapeRight){
                _deviceOrientation = AVCaptureVideoOrientationLandscapeRight;//手机左放（眼对着屏幕）
            }
        }else if ((device_angle > M_PI_4) && (device_angle < 3 * M_PI_4)){
            if(_deviceOrientation != AVCaptureVideoOrientationLandscapeLeft){
                _deviceOrientation = AVCaptureVideoOrientationLandscapeLeft;//手机右放（眼对着屏幕）
            }
        }else{
            if(_deviceOrientation != AVCaptureVideoOrientationPortrait){
                _deviceOrientation = AVCaptureVideoOrientationPortrait;//手机右放（眼对着屏幕）
            }
        }
    } else {
        if ( (device_angle > -M_PI_4) && (device_angle < M_PI_4) ){
            if(_deviceOrientation != AVCaptureVideoOrientationPortraitUpsideDown){
                _deviceOrientation = AVCaptureVideoOrientationPortraitUpsideDown;//手机右放（眼对着屏幕）
            }
        }else if ((device_angle < -M_PI_4) && (device_angle > -3 * M_PI_4)){
            if(_deviceOrientation != AVCaptureVideoOrientationLandscapeRight){
                _deviceOrientation = AVCaptureVideoOrientationLandscapeRight;//手机右放（眼对着屏幕）
            }
        }else if ((device_angle > M_PI_4) && (device_angle < 3 * M_PI_4)){
            if(_deviceOrientation != AVCaptureVideoOrientationLandscapeLeft){
                _deviceOrientation = AVCaptureVideoOrientationLandscapeLeft;//手机右放（眼对着屏幕）
            }
        }else{
            if(_deviceOrientation != AVCaptureVideoOrientationPortrait){
                _deviceOrientation = AVCaptureVideoOrientationPortrait;//手机右放（眼对着屏幕）
            }
        }
    }
}

-(void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex{
    if(alertView.tag == SKTagSetAlert){
        if(buttonIndex==1) {
            NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
            [[UIApplication sharedApplication] openURL:url];
        }else{
            self.hidden = YES;
        }
    }else if (alertView.tag == SKTagCompressAlert){
    }
}

-(void)cancelAction{
    [self hidden:YES];
}

-(void)hidden:(BOOL)hidden{
    self.hidden = hidden;
    if (hidden == YES) {
        [self CMMotionStop];
        [self.session stopRunning];
    }else{
        [self CMMotionStart];
        [self.session startRunning];
    }
}

-(void)setFrame:(CGRect)frame{
    [super setFrame:frame];
    self.effectiveScale = self.beginGestureScale = 1.0f;
    [self.previewLayer setAffineTransform:CGAffineTransformMakeScale(self.effectiveScale, self.effectiveScale)];
    [self reloadFram];
    [UIView animateWithDuration:0.5 animations:^{
        [self.previewLayer setFrame:CGRectMake(0, 0, frame.size.width, frame.size.height)];
    } completion:^(BOOL finished) {
    }];
}

-(void)reloadFram{
    CGFloat iconWH = 40 / SKCameraViewScreenHeight * self.frame.size.height;
    self.cameraView.frame = CGRectMake(0, 0, SKVIEW_W(self), SKVIEW_H(self));
    self.takePicBtn.frame = CGRectMake((SKVIEW_W(self) - 50)/2.f, SKVIEW_H(self) - 50 - 5, 50, 50);
    self.changeCameraBtn.frame = CGRectMake(SKVIEW_W(self) - iconWH - 5, 5, iconWH, iconWH);
    self.flashButton.frame = CGRectMake(5, 5, iconWH, iconWH);
    CGFloat wideB = SKVIEW_W(self) - (5 + iconWH/2.f) * 2;
    
    self.netBtn.frame = CGRectMake(5 + iconWH/2.f + (wideB/3.f)*2 - iconWH/2.f, 5, iconWH, iconWH);
    _compressBtn.titleLabel.font = [UIFont systemFontOfSize:16];
    CGFloat comWide = [self countTextCGSize:[UIFont systemFontOfSize:16] viewHeight:20 text:@"高清"].width;
    self.compressBtn.frame = CGRectMake(SKVIEW_W(self) - comWide - SKMarginA, 5, comWide, iconWH);
    
    float crossWide = SKVIEW_H(self)/(SKNumCross + 1);
    for (int i = 0; i < SKNumCross; i ++) {
        UIView *view = [self.cameraView viewWithTag:SKTagCross + i];
        view.frame = CGRectMake(0, crossWide * (i + 1), 0, 0.5);
    }
    float verWide = SKVIEW_W(self)/(SKNumVertical + 1);
    for (int i = 0; i < SKNumVertical; i ++) {
        UIView *view = [self.cameraView viewWithTag:SKTagVertical + i];
        view.frame = CGRectMake(verWide *(i + 1), 0, 0.5, 0);
    }
}

#pragma mark 闪光灯
- (void)FlashOn{
    _flashButton.selected = !_flashButton.selected;
    if ([_device lockForConfiguration:nil]) {
        if (!_flashButton.selected) {
            if ([_device isFlashModeSupported:AVCaptureFlashModeOff]) {
                [_device setFlashMode:AVCaptureFlashModeOff];
            }
        }else{
            if ([_device isFlashModeSupported:AVCaptureFlashModeOn]) {
                [_device setFlashMode:AVCaptureFlashModeOn];
            }
        }
        [_device unlockForConfiguration];
    }
}

#pragma mark 网格
-(void)netBtnClcik{
    _netBtn.selected = !_netBtn.selected;
    if (_netBtn.selected) {
        [self netViewShow];
    }else{
        [self netViewHidden];
    }
}

-(void)netViewShow{
    for (int i = 0; i < SKNumCross; i ++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * i * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *view = [self.cameraView viewWithTag:SKTagCross + i];
            view.hidden = NO;
            [UIView animateWithDuration:0.4 animations:^{
                view.frame = CGRectMake(CGRectGetMinX(view.frame), CGRectGetMinY(view.frame), SKVIEW_W(self), SKVIEW_H(view));
            }];
        });
    }
    for (int i = 0; i < SKNumVertical; i ++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * i * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *view = [self.cameraView viewWithTag:SKTagVertical + i];
            view.hidden = NO;
            [UIView animateWithDuration:0.4 animations:^{
                view.frame = CGRectMake(CGRectGetMinX(view.frame), CGRectGetMinY(view.frame), SKVIEW_W(view), SKVIEW_H(self));
            }];
        });
        
    }
}

-(void)netViewHidden{
    for (int i = 0; i < SKNumCross; i ++) {
        UIView *view = [self.cameraView viewWithTag:SKTagCross + i];
        [UIView animateWithDuration:0.2 animations:^{
            view.frame = CGRectMake(CGRectGetMinX(view.frame), CGRectGetMinY(view.frame), 0, SKVIEW_H(view));
        } completion:^(BOOL finished) {
            view.hidden = YES;
        }];
    }
    for (int i = 0; i < SKNumVertical; i ++) {
        UIView *view = [self.cameraView viewWithTag:SKTagVertical + i];
        [UIView animateWithDuration:0.2 animations:^{
            view.frame = CGRectMake(CGRectGetMinX(view.frame), CGRectGetMinY(view.frame), SKVIEW_W(view), 0);
        } completion:^(BOOL finished) {
            view.hidden = YES;
        }];
    }
}

#pragma mark 压缩比
-(void)compressBtnClcik{
    _compressBtn.selected = !_compressBtn.selected;
}

// 计算文字的CGSize (高固定)
- (CGSize)countTextCGSize:(UIFont *)font
               viewHeight:(CGFloat)viewHeight
                     text:(NSString *)text {
    if (!font) return CGSizeZero;
    
    CGSize size = CGSizeMake(MAXFLOAT,viewHeight);
    
    //计算实际frame大小，并将label的frame变成实际大小
    CGSize txtSize;
    NSStringDrawingOptions options = NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading;
    CGRect txtRT = [text boundingRectWithSize:size options:options attributes:@{NSFontAttributeName:font} context:nil];
    txtSize = txtRT.size;
    return txtSize;
}



@end
