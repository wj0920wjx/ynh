//
//  ViewController.m
//  ynh
//
//  Created by 王杰 on 2017/10/22.
//  Copyright © 2017年 王杰. All rights reserved.
//

#import "ViewController.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import <WXApi.h>
#import "WXApiManager.h"
#import <AlipaySDK/AlipaySDK.h>
#import "APOrderInfo.h"
#import "APRSASigner.h"

#define HTMLURL @"http://ynh.iso315.org/ShopM/Index"
@interface ViewController ()<UIWebViewDelegate,WXApiManagerDelegate>

@property (strong, nonatomic) UIWebView *webView;

@end

@implementation ViewController{
    JSContext *jscontext;
    BOOL isFirst;
    NSString *orderId;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    isFirst = YES;
    [self loadWebView];
    [WXApiManager sharedManager].delegate = self;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(aliPayResult:)name:@"aliPayResult" object:nil];
}

-(UIWebView *)webView{
    if (!_webView) {
        _webView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 20, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height-20)];
        _webView.delegate = self;
    }
    return _webView;
}

-(void)loadWebView{
    [self.view addSubview:self.webView];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:HTMLURL] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60.0];
    
    [self.webView loadRequest:request];
    
    self.webView.scrollView.bounces = NO;
    
    self.webView.dataDetectorTypes = UIDataDetectorTypeNone;
    
    jscontext = [[JSContext alloc] init];
    jscontext =  [self.webView valueForKeyPath:@"documentView.webView.mainFrame.javaScriptContext"];
}

-(BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType{
    return YES;
}

-(void)webViewDidStartLoad:(UIWebView *)webView{
    //显示网络请求加载
    [UIApplication sharedApplication].networkActivityIndicatorVisible=true;
    
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

-(void)webViewDidFinishLoad:(UIWebView *)webView{
    __weak typeof(self) wself = self;
    jscontext[@"WeichatLogin"] = ^() {
        [wself sendAuthRequest];
    };
    jscontext[@"aliPay"] = ^() {
        //        [wself sendAuthRequest];
        NSArray *args = [JSContext currentArguments];
        if (args.count < 1) {
            return ;
        }
        NSString *jsonString = [args[0] toString];
        NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error;
        NSDictionary *objc = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
        
        NSLog(@"%@",objc);
        [wself doAPPay:objc];
    };
    jscontext[@"wxPay"] = ^() {
        NSArray *args = [JSContext currentArguments];
        if (args.count < 1) {
            return ;
        }
        NSString *jsonString = [args[0] toString];
        NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error;
        NSDictionary *objc = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
        
        NSLog(@"%@",objc);
        [wself jumpToBizWxPay:objc];
    };
    jscontext.exceptionHandler = ^(JSContext *context, JSValue *exceptionValue) {
        context.exception = exceptionValue;
        NSLog(@"异常信息：%@", exceptionValue);
    };
    
    jscontext[@"tokenError"] = ^() {
        //失效处理
    };
    
    //隐藏网络请求加载图标
    [UIApplication sharedApplication].networkActivityIndicatorVisible=false;
    //设置按钮状态
}

-(void)sendAuthRequest
{
    BOOL isStaillWX = YES;//[WXApi isWXAppInstalled]; -- 不能使用?
    
    if (isStaillWX) {
        //构造SendAuthReq结构体
        SendAuthReq* req =[[SendAuthReq alloc ] init];
        req.scope = @"snsapi_userinfo" ;
        req.state = @"wjx" ;
        //第三方向微信终端发送一个SendAuthReq消息结构
        [WXApi sendReq:req];
    }
    else{
        NSLog(@"未安装微信");
    }
}

//加入首次安装无网络提示 -- 晚上 -- 微信登录
- (void)managerDidRecvAuthResponse:(SendAuthResp *)response {
    NSString *strTitle = [NSString stringWithFormat:@"Auth结果"];
    NSString *strMsg = [NSString stringWithFormat:@"code:%@,state:%@,errcode:%d", response.code, response.state, response.errCode];
    
    NSLog(@"***********%@*******%@******",strTitle,strMsg);
    
    NSString *textJS = [NSString stringWithFormat:@"login('%@')",response.code];
    [jscontext evaluateScript:textJS];
}

//微信支付回调
-(void)managerPay:(PayResp *)response{
    //支付返回结果，实际支付结果需要去微信服务器端查询
    NSString *strMsg;
    
    switch (response.errCode) {
        case WXSuccess:
            strMsg = @"支付成功";
            break;
        case WXErrCodeUserCancel:
            strMsg = @"用户取消";
            break;
        case WXErrCodeCommon:
            strMsg = @"支付错误";
            break;
        default:
            strMsg = @"支付失败";
            break;
    }
    
    NSString *textJS = [NSString stringWithFormat:@"wxPayResult(\"{'errCode':'%@','errStr':'%@','orderId':'%@'}\");",[NSString stringWithFormat:@"%d",response.errCode],strMsg,orderId];
    //防止页面卡死 -- 需要使用js的方法减缓一秒执行
    NSString *jsMyAlert =[NSString stringWithFormat:@"setTimeout(function(){%@;},1)",textJS];
    
    [self.webView stringByEvaluatingJavaScriptFromString:jsMyAlert];
}

//微信支付
- (void)jumpToBizWxPay:(NSDictionary *)dict{
    NSString *retcode = [NSString stringWithFormat:@"%@",dict[@"code"]];
    if (retcode.intValue == 0){
        if(dict != nil){
            NSMutableString *stamp  = [dict objectForKey:@"timestamp"];
            
            //调起微信支付
            PayReq* req             = [[PayReq alloc] init];
            req.partnerId           = [dict objectForKey:@"partnerid"];
            req.prepayId            = [dict objectForKey:@"prepayid"];
            orderId = [dict objectForKey:@"orderId"];
            req.nonceStr            = [dict objectForKey:@"noncestr"];
            req.timeStamp           = stamp.intValue;
            req.package             = [dict objectForKey:@"package"];
            req.sign                = [dict objectForKey:@"sign"];
            [WXApi sendReq:req];
            
            //日志输出
            NSLog(@"appid=%@\npartid=%@\nprepayid=%@\nnoncestr=%@\ntimestamp=%ld\npackage=%@\nsign=%@",[dict objectForKey:@"appid"],req.partnerId,req.prepayId,req.nonceStr,(long)req.timeStamp,req.package,req.sign );
        }
    }
}

-(void)aliPayResult:(NSNotification *)notice{
    NSDictionary *dict = notice.userInfo;
    NSLog(@"%@",dict);
    NSString *strMsg;
    
    switch ([dict[@"resultStatus"] integerValue]) {
        case 9000:
            strMsg = @"支付成功";
            break;
        case 8000:
            strMsg = @"支付结果确认中";
            break;
        case 4000:
            strMsg = @"请确认是否安装支付宝";
            break;
        case -1:
            strMsg = @"支付失败";
            break;
        default:
            strMsg = dict[@"memo"];
            break;
    }

    NSString *textJS = [NSString stringWithFormat:@"aliPayResult(\"{'errCode':'%@','errStr':'%@','orderId':'%@'}\");",notice.userInfo[@"resultStatus"],strMsg,orderId];
    //防止页面卡死 -- 需要使用js的方法减缓一秒执行
    NSString *jsMyAlert =[NSString stringWithFormat:@"setTimeout(function(){%@;},1)",textJS];

    [self.webView stringByEvaluatingJavaScriptFromString:jsMyAlert];
}

-(void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"aliPayResult" object:nil];
}

//支付宝支付
- (void)doAPPay:(NSDictionary *)dict
{
    orderId = [dict objectForKey:@"orderId"];
    
    NSString *appScheme = @"2017110209672766";
    
    // NOTE: 将签名成功字符串格式化为订单字符串,请严格按照该格式
    NSString *orderString = dict[@"payInfo"];
    
    // NOTE: 调用支付结果开始支付
    [[AlipaySDK defaultService] payOrder:orderString fromScheme:appScheme callback:^(NSDictionary *resultDic) {
        NSLog(@"reslut = %@",resultDic);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"aliPayResult" object:nil userInfo:resultDic];
    }];
}

- (NSString *)generateTradeNO
{
    static int kNumber = 15;
    NSString *sourceStr = @"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    NSMutableString *resultStr = [[NSMutableString alloc] init];
    srand((unsigned)time(0));
    for (int i = 0; i < kNumber; i++)
    {
        unsigned index = rand() % [sourceStr length];
        NSString *oneStr = [sourceStr substringWithRange:NSMakeRange(index, 1)];
        [resultStr appendString:oneStr];
    }
    return resultStr;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

