//
//  SKCameraView.h
//  duoduo
//
//  Created by ac hu on 2017/11/20.
//  Copyright © 2017年 Locke. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SKCameraView : UIView

//压缩比,默认不压缩，这里和选择是否高清关联
@property (nonatomic,assign)float imageCompress;
@property(nonatomic,copy)void (^donePic)(UIImage *image,float compress);
@property(nonatomic,copy)void (^scaleSmallBlcok)(BOOL isSmall);

+(instancetype)share;
-(void)cancelAction;
@end
