//
//  SKCameraView.h
//  duoduo
//
//  Created by ac hu on 2017/11/20.
//  Copyright © 2017年 Locke. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SKCameraView : UIView

@property(nonatomic,copy)void (^donePic)(UIImage *image,float compress);
@property(nonatomic,copy)void (^scaleSmallBlcok)(BOOL isSmall);

+(instancetype)share;
-(void)cancelAction;
@end
