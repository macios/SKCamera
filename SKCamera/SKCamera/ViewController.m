//
//  ViewController.m
//  SKCamera
//
//  Created by ac-hu on 2018/11/6.
//  Copyright © 2018年 SK-HU. All rights reserved.
//

#import "ViewController.h"
#import "SKCameraView.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    SKCameraView *view = [SKCameraView share];
    
    view.frame = CGRectMake((self.view.bounds.size.width - 200) / 2.f, (self.view.bounds.size.height - 500) / 2.f, 200, 500);
    [self.view addSubview:view];
    [view setHidden:NO];
//    [view scaleBtnClcik];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
