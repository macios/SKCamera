//
//  UIImage+SKImage.h
//  SKCamera
//
//  Created by ac-hu on 2018/11/7.
//  Copyright © 2018年 SK-HU. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIImage (SKImage)
//纠正方向
- (UIImage *)fixOrientation;

//按视图宽高裁剪
- (UIImage*)imageTailorSize:(CGSize)viewSize;
@end
