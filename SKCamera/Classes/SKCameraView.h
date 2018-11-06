//
//  SKCameraView.h
//  duoduo
//
//  Created by ac hu on 2017/11/20.
//  Copyright © 2017年 Locke. All rights reserved.
//

#import <UIKit/UIKit.h>



// 拍照类型
typedef enum {
    HuTakePictureTypeNone = 1,// 普通拍照
    HuTakePictureTypeOCR = 2,// OCR拍照
}HuTakePictureType;

@interface SKCameraView : UIView


@property(nonatomic,copy)void (^donePic)(UIImage *image,HuTakePictureType type,float compress);
@property(nonatomic,copy)void (^scaleSmallBlcok)(BOOL isSmall);

+(instancetype)share;
-(void)hidden:(BOOL)hidden;
-(void)cancelAction;
-(void)smallView;
-(void)scaleSmall;
-(void)scaleBtnClcik;
@end
