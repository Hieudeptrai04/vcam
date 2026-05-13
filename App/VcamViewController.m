#import "VcamViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const kConfigPath = @"/var/jb/etc/vcam/config.plist";
static NSString *const kConfigDir  = @"/var/jb/etc/vcam";
static NSString *const kDefaultVideoPath = @"/var/jb/etc/vcam/video.mp4";

@interface VcamViewController ()
@property (nonatomic, strong) UISwitch    *enabledSwitch;
@property (nonatomic, strong) UITextField *pathField;
@property (nonatomic, strong) UILabel     *statusLabel;
@property (nonatomic, strong) UIButton    *pickButton;
@property (nonatomic, strong) UIButton    *saveButton;
@end

@implementation VcamViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"VcamFullMay";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self buildUI];
    [self loadConfig];
    [self refreshStatus];
}

- (void)buildUI {
    CGFloat margin = 20;
    CGFloat y = 100;
    CGFloat w = self.view.bounds.size.width - margin * 2;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, w, 32)];
    title.text = @"Virtual Camera";
    title.font = [UIFont boldSystemFontOfSize:22];
    [self.view addSubview:title];
    y += 50;

    UILabel *enLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, w - 80, 32)];
    enLabel.text = @"Bật vcam";
    enLabel.font = [UIFont systemFontOfSize:17];
    [self.view addSubview:enLabel];

    self.enabledSwitch = [[UISwitch alloc] initWithFrame:
        CGRectMake(self.view.bounds.size.width - margin - 60, y, 60, 32)];
    [self.view addSubview:self.enabledSwitch];
    y += 50;

    UILabel *pathLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, w, 24)];
    pathLabel.text = @"Đường dẫn video:";
    pathLabel.font = [UIFont systemFontOfSize:15];
    pathLabel.textColor = [UIColor secondaryLabelColor];
    [self.view addSubview:pathLabel];
    y += 28;

    self.pathField = [[UITextField alloc] initWithFrame:CGRectMake(margin, y, w, 40)];
    self.pathField.borderStyle = UITextBorderStyleRoundedRect;
    self.pathField.placeholder = kDefaultVideoPath;
    self.pathField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.pathField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.pathField.font = [UIFont systemFontOfSize:14];
    self.pathField.delegate = self;
    [self.view addSubview:self.pathField];
    y += 50;

    self.pickButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.pickButton.frame = CGRectMake(margin, y, w, 44);
    [self.pickButton setTitle:@"Chọn video từ Files…" forState:UIControlStateNormal];
    self.pickButton.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.pickButton.layer.cornerRadius = 8;
    [self.pickButton addTarget:self action:@selector(pickVideo)
              forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.pickButton];
    y += 56;

    self.saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.saveButton.frame = CGRectMake(margin, y, w, 50);
    [self.saveButton setTitle:@"LƯU CẤU HÌNH" forState:UIControlStateNormal];
    [self.saveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.saveButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    self.saveButton.backgroundColor = [UIColor systemPurpleColor];
    self.saveButton.layer.cornerRadius = 10;
    [self.saveButton addTarget:self action:@selector(saveConfig)
              forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.saveButton];
    y += 70;

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, w, 120)];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    [self.view addSubview:self.statusLabel];
}

- (void)loadConfig {
    NSDictionary *cfg = [NSDictionary dictionaryWithContentsOfFile:kConfigPath];
    if (cfg) {
        id e = cfg[@"enabled"];
        self.enabledSwitch.on = e ? [e boolValue] : YES;
        NSString *p = cfg[@"videoPath"];
        if (p.length > 0) self.pathField.text = p;
    } else {
        self.enabledSwitch.on = YES;
    }
}

- (void)refreshStatus {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"Config: %@\n",
        [fm fileExistsAtPath:kConfigPath] ? @"đã có" : @"chưa có"];
    NSString *checkPath = self.pathField.text.length > 0
        ? self.pathField.text
        : kDefaultVideoPath;
    BOOL videoOK = [fm fileExistsAtPath:checkPath];
    [s appendFormat:@"Video: %@\n", videoOK ? @"đã có" : @"chưa có"];
    [s appendFormat:@"Path: %@\n", checkPath];
    if (!videoOK) {
        [s appendString:@"\n⚠ Đặt video.mp4 vào path trên trước khi mở Zalo/FB/IG."];
    }
    self.statusLabel.text = s;
}

#pragma mark - Actions

- (void)pickVideo {
    UTType *mov = [UTType typeWithIdentifier:@"public.movie"];
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[mov]];
    p.delegate = self;
    p.allowsMultipleSelection = NO;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)saveConfig {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    if (![fm fileExistsAtPath:kConfigDir]) {
        [fm createDirectoryAtPath:kConfigDir
      withIntermediateDirectories:YES attributes:nil error:&err];
    }

    NSString *path = self.pathField.text;
    if (path.length == 0) path = kDefaultVideoPath;
    NSDictionary *cfg = @{
        @"enabled":   @(self.enabledSwitch.on),
        @"videoPath": path,
    };

    BOOL ok = [cfg writeToFile:kConfigPath atomically:YES];
    NSString *msg = ok
        ? @"Đã lưu vào /var/jb/etc/vcam/config.plist\n\nMở lại app camera để áp dụng."
        : @"Lưu thất bại — app có thể không đủ quyền ghi /var/jb/etc/vcam.\n\nThử SSH chmod 777 /var/jb/etc/vcam hoặc chạy:\nsudo mkdir -p /var/jb/etc/vcam && sudo chmod 777 /var/jb/etc/vcam";

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:(ok ? @"OK" : @"Lỗi")
        message:msg
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK"
                                          style:UIAlertActionStyleDefault
                                        handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
    [self refreshStatus];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller
        didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSURL *src = urls.firstObject;
    if (!src) return;
    [src startAccessingSecurityScopedResource];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    if (![fm fileExistsAtPath:kConfigDir]) {
        [fm createDirectoryAtPath:kConfigDir
      withIntermediateDirectories:YES attributes:nil error:&err];
    }
    NSString *dest = [kConfigDir stringByAppendingPathComponent:@"video.mp4"];
    [fm removeItemAtPath:dest error:nil];
    BOOL ok = [fm copyItemAtPath:src.path toPath:dest error:&err];
    [src stopAccessingSecurityScopedResource];
    if (ok) {
        self.pathField.text = dest;
    }
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:(ok ? @"Đã copy video" : @"Lỗi copy")
        message:ok ? dest : err.localizedDescription
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK"
                                          style:UIAlertActionStyleDefault
                                        handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
    [self refreshStatus];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self refreshStatus];
    return YES;
}

@end
