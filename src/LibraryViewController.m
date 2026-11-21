#import "LibraryViewController.h"
#import "ReaderViewController.h"
#import "Models.h"
#import "PDFDoc.h"
#import "PDFIcons.h"
#import "LibraryNames.h"

typedef NS_ENUM(NSInteger, LibrarySortOrder) {
    LibrarySortByName = 0,
    LibrarySortByDate = 1,
    LibrarySortBySize = 2,
};

static NSString *const kPrefLibrarySortKey = @"library.sortOrder";

@interface PDFLibraryItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *fullPath;
@property (nonatomic, copy) NSString *relativeFolder;
@property (nonatomic, assign) BOOL isDirectory;
@property (nonatomic, assign) unsigned long long fileSize;
@property (nonatomic, strong) NSDate *modDate;
@property (nonatomic, assign) BOOL hasAnnotations;
@property (nonatomic, assign) NSInteger lastPage;
@property (nonatomic, assign) NSInteger cachedPageCount; // -1 if not yet queried
@end

@implementation PDFLibraryItem
@end

@interface PDFLibraryCell : UITableViewCell
@property (nonatomic, strong) UIImageView *coverView;
@property (nonatomic, strong) UILabel *titleLbl;
@property (nonatomic, strong) UILabel *metaLbl;
@property (nonatomic, strong) UILabel *badgeLbl;
@property (nonatomic, copy) NSString *representedPath;
@end

@implementation PDFLibraryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _coverView = [[UIImageView alloc] initWithFrame:CGRectMake(14.0f, 7.0f, 40.0f, 54.0f)];
        _coverView.contentMode = UIViewContentModeScaleAspectFit;
        _coverView.clipsToBounds = YES;
        _coverView.layer.cornerRadius = 4.0f;
        [self.contentView addSubview:_coverView];

        _titleLbl = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLbl.font = [UIFont boldSystemFontOfSize:15.5f];
        _titleLbl.textColor = [UIColor colorWithWhite:0.10f alpha:1.0f];
        [self.contentView addSubview:_titleLbl];

        _metaLbl = [[UILabel alloc] initWithFrame:CGRectZero];
        _metaLbl.font = [UIFont systemFontOfSize:12.5f];
        _metaLbl.textColor = [UIColor colorWithWhite:0.46f alpha:1.0f];
        [self.contentView addSubview:_metaLbl];

        _badgeLbl = [[UILabel alloc] initWithFrame:CGRectZero];
        _badgeLbl.font = [UIFont boldSystemFontOfSize:11.0f];
        _badgeLbl.textColor = [UIColor colorWithRed:0.12f green:0.45f blue:0.92f alpha:1.0f];
        _badgeLbl.backgroundColor = [UIColor colorWithRed:0.14f green:0.48f blue:0.96f alpha:0.12f];
        _badgeLbl.textAlignment = NSTextAlignmentCenter;
        _badgeLbl.layer.cornerRadius = 6.0f;
        _badgeLbl.clipsToBounds = YES;
        _badgeLbl.hidden = YES;
        [self.contentView addSubview:_badgeLbl];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize sz = self.contentView.bounds.size;
    _coverView.frame = CGRectMake(14.0f, floorf((float)((sz.height - 52.0f) * 0.5f)), 40.0f, 52.0f);

    CGFloat rightEdge = sz.width - 12.0f;
    if (!_badgeLbl.hidden) {
        [_badgeLbl sizeToFit];
        CGFloat bw = _badgeLbl.bounds.size.width + 14.0f;
        _badgeLbl.frame = CGRectMake(rightEdge - bw, floorf((float)((sz.height - 22.0f) * 0.5f)), bw, 22.0f);
        rightEdge = _badgeLbl.frame.origin.x - 8.0f;
    }

    CGFloat textX = 66.0f;
    CGFloat textW = MAX(80.0f, rightEdge - textX);
    _titleLbl.frame = CGRectMake(textX, 13.0f, textW, 21.0f);
    _metaLbl.frame = CGRectMake(textX, 36.0f, textW, 18.0f);
}

@end

@interface LibraryViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@end

@implementation LibraryViewController {
    UITableView *_tableView;
    UISearchBar *_searchBar;
    UIRefreshControl *_refreshControl;
    UILabel *_emptyLabel;

    NSMutableArray<PDFLibraryItem *> *_allItems;
    NSMutableArray<PDFLibraryItem *> *_filteredItems;
    LibrarySortOrder _sortOrder;
    NSString *_searchQuery;

    NSCache *_coverCache;
    NSMutableDictionary<NSString *, NSNumber *> *_pageCountCache;
}

- (instancetype)init {
    return [self initWithDirectory:[AnnotationStore documentsDirectory]];
}

- (instancetype)initWithDirectory:(NSString *)directoryPath {
    self = [super init];
    if (self) {
        _directoryPath = [(directoryPath ?: [AnnotationStore documentsDirectory]) copy];
        _allItems = [NSMutableArray array];
        _filteredItems = [NSMutableArray array];
        _coverCache = [[NSCache alloc] init];
        _coverCache.countLimit = 64;
        _coverCache.totalCostLimit = 4 * 1024 * 1024;
        _pageCountCache = [NSMutableDictionary dictionary];
        _sortOrder = (LibrarySortOrder)[[NSUserDefaults standardUserDefaults] integerForKey:kPrefLibrarySortKey];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isRootLibrary {
    NSString *docs = [AnnotationStore documentsDirectory];
    NSString *cur = [_directoryPath stringByResolvingSymlinksInPath] ?: [_directoryPath stringByStandardizingPath];
    return [cur isEqualToString:docs];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.95f green:0.95f blue:0.97f alpha:1.0f];

    self.title = [self isRootLibrary] ? @"PDF Notes" : [_directoryPath lastPathComponent];

    UIBarButtonItem *addBtn = [[UIBarButtonItem alloc] initWithImage:PDFIconPlus()
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(addButtonTapped:)];
    UIBarButtonItem *sortBtn = [[UIBarButtonItem alloc] initWithImage:PDFIconSort()
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(sortButtonTapped:)];
    self.navigationItem.rightBarButtonItems = @[ addBtn, sortBtn ];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 68.0f;
    _tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [_tableView registerClass:[PDFLibraryCell class] forCellReuseIdentifier:@"LibCell"];
    [self.view addSubview:_tableView];

    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0.0f, 0.0f, self.view.bounds.size.width, 44.0f)];
    _searchBar.placeholder = [self isRootLibrary] ? @"Search all PDFs & folders…" : @"Search in this folder…";
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.delegate = self;
    _tableView.tableHeaderView = _searchBar;

    _refreshControl = [[UIRefreshControl alloc] init];
    [_refreshControl addTarget:self action:@selector(pullToRefreshTriggered) forControlEvents:UIControlEventValueChanged];
    [_tableView addSubview:_refreshControl];

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleRowLongPress:)];
    [_tableView addGestureRecognizer:lp];

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 36.0f, 80.0f)];
    _emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.font = [UIFont systemFontOfSize:15.0f];
    _emptyLabel.textColor = [UIColor colorWithWhite:0.46f alpha:1.0f];
    _emptyLabel.userInteractionEnabled = NO;
    [self.view addSubview:_emptyLabel];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [self sweepInboxIfNeeded];
    [self reloadFiles];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [_coverCache removeAllObjects];
}

- (void)appDidBecomeActive {
    [self sweepInboxIfNeeded];
    [self reloadFiles];
}

- (void)pullToRefreshTriggered {
    [self sweepInboxIfNeeded];
    [self reloadFiles];
    [_refreshControl endRefreshing];
}

#pragma mark - Inbox Import & Directory Scanning

- (void)sweepInboxIfNeeded {
    if (![self isRootLibrary]) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *docs = [AnnotationStore documentsDirectory];
    NSString *inbox = [docs stringByAppendingPathComponent:@"Inbox"];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:inbox isDirectory:&isDir] || !isDir) return;

    NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:inbox error:NULL];
    for (NSString *name in items) {
        if ([name hasPrefix:@"."]) continue;
        NSString *src = [inbox stringByAppendingPathComponent:name];
        if (![[name.pathExtension lowercaseString] isEqualToString:@"pdf"]) {
            [fm removeItemAtPath:src error:NULL];
            continue;
        }
        NSString *dest = [self uniqueDestinationInDirectory:docs forFilename:name];
        [fm moveItemAtPath:src toPath:dest error:NULL];
    }
}

- (NSString *)uniqueDestinationInDirectory:(NSString *)dir forFilename:(NSString *)filename {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *base = [filename stringByDeletingPathExtension];
    NSString *ext = [filename pathExtension];
    if (base.length == 0) base = @"Document";
    NSString *candidate = [dir stringByAppendingPathComponent:filename];
    NSInteger idx = 2;
    while ([fm fileExistsAtPath:candidate]) {
        NSString *numbered = ext.length > 0
            ? [NSString stringWithFormat:@"%@-%ld.%@", base, (long)idx++, ext]
            : [NSString stringWithFormat:@"%@-%ld", base, (long)idx++];
        candidate = [dir stringByAppendingPathComponent:numbered];
    }
    return candidate;
}

- (void)collectItemsInDirectory:(NSString *)dir
                 relativePrefix:(NSString *)relPrefix
                      recursive:(BOOL)recursive
                           into:(NSMutableArray<PDFLibraryItem *> *)outArray {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:dir error:NULL];
    NSString *docs = [AnnotationStore documentsDirectory];
    BOOL atRoot = [[dir stringByResolvingSymlinksInPath] isEqualToString:docs];

    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;
        if (atRoot && ([name isEqualToString:@"Inbox"] || [name isEqualToString:@"Annotations"])) {
            continue;
        }

        NSString *full = [dir stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDir]) continue;

        if (!isDir && ![[name.pathExtension lowercaseString] isEqualToString:@"pdf"]) {
            continue;
        }

        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:NULL];
        PDFLibraryItem *item = [[PDFLibraryItem alloc] init];
        item.name = isDir ? name : [name stringByDeletingPathExtension];
        item.fullPath = full;
        item.relativeFolder = relPrefix;
        item.isDirectory = isDir;
        item.fileSize = [attrs[NSFileSize] unsignedLongLongValue];
        item.modDate = attrs[NSFileModificationDate] ?: [NSDate distantPast];
        item.cachedPageCount = _pageCountCache[full] ? [_pageCountCache[full] integerValue] : -1;

        if (!isDir) {
            item.hasAnnotations = [AnnotationStore hasSavedAnnotationsForPDFPath:full];
            item.lastPage = [AnnotationStore savedLastPageForPDFPath:full];
        }
        [outArray addObject:item];

        if (isDir && recursive) {
            NSString *nextRel = relPrefix.length > 0 ? [relPrefix stringByAppendingPathComponent:name] : name;
            [self collectItemsInDirectory:full relativePrefix:nextRel recursive:YES into:outArray];
        }
    }
}

- (void)reloadFiles {
    [_allItems removeAllObjects];
    BOOL searchingAll = (_searchQuery.length > 0 && [self isRootLibrary]);
    [self collectItemsInDirectory:_directoryPath relativePrefix:@"" recursive:searchingAll into:_allItems];
    [self applySortAndFilter];
}

- (void)applySortAndFilter {
    NSString *q = [_searchQuery stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [_filteredItems removeAllObjects];

    for (PDFLibraryItem *item in _allItems) {
        if (q.length > 0) {
            NSRange r1 = [item.name rangeOfString:q options:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)];
            NSRange r2 = [item.relativeFolder rangeOfString:q options:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)];
            if (r1.location == NSNotFound && r2.location == NSNotFound) continue;
        }
        [_filteredItems addObject:item];
    }

    LibrarySortOrder order = _sortOrder;
    [_filteredItems sortUsingComparator:^NSComparisonResult(PDFLibraryItem *a, PDFLibraryItem *b) {
        // Always keep folders grouped at the top
        if (a.isDirectory != b.isDirectory) {
            return a.isDirectory ? NSOrderedAscending : NSOrderedDescending;
        }
        if (order == LibrarySortByDate) {
            NSComparisonResult dr = [b.modDate compare:a.modDate];
            if (dr != NSOrderedSame) return dr;
        } else if (order == LibrarySortBySize && !a.isDirectory) {
            if (a.fileSize != b.fileSize) {
                return (b.fileSize > a.fileSize) ? NSOrderedAscending : NSOrderedDescending;
            }
        }
        return [a.name localizedStandardCompare:b.name];
    }];

    [_tableView reloadData];

    if (_filteredItems.count == 0) {
        _emptyLabel.hidden = NO;
        if (q.length > 0) {
            _emptyLabel.text = [NSString stringWithFormat:@"No PDFs or folders matching \"%@\".", q];
        } else {
            _emptyLabel.text = @"No PDFs in this folder yet.\n\nTap + at the top right to create a Blank, Ruled, Grid, or Cornell Notebook — or import PDFs via iTunes File Sharing, Safari \"Copy to PDF Notes\", or Filza.";
        }
    } else {
        _emptyLabel.hidden = YES;
    }
}

#pragma mark - Search & Sort

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    _searchQuery = [searchText copy];
    [self reloadFiles];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)sortButtonTapped:(UIBarButtonItem *)sender {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Sort Library By"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[
        (_sortOrder == LibrarySortByName) ? @"✓ Name (A–Z)" : @"Name (A–Z)",
        (_sortOrder == LibrarySortByDate) ? @"✓ Date Modified (Newest)" : @"Date Modified (Newest)",
        (_sortOrder == LibrarySortBySize) ? @"✓ File Size (Largest)" : @"File Size (Largest)",
    ];
    for (NSInteger i = 0; i < 3; i++) {
        [ac addAction:[UIAlertAction actionWithTitle:titles[(NSUInteger)i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            self->_sortOrder = (LibrarySortOrder)i;
            [[NSUserDefaults standardUserDefaults] setInteger:i forKey:kPrefLibrarySortKey];
            [self applySortAndFilter];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    ac.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Add Menu (New Notebook PDF & New Folder)

- (void)addButtonTapped:(UIBarButtonItem *)sender {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Create or Import"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"New Ruled Notebook…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf promptCreateNotebookWithStyle:PDFNotebookTemplateRuled defaultTitle:@"Ruled Notes"];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"New Graph Grid Notebook…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf promptCreateNotebookWithStyle:PDFNotebookTemplateGrid defaultTitle:@"Grid Notes"];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"New Dot Grid Notebook…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf promptCreateNotebookWithStyle:PDFNotebookTemplateDotted defaultTitle:@"Dot Notes"];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"New Cornell Notes…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf promptCreateNotebookWithStyle:PDFNotebookTemplateCornell defaultTitle:@"Cornell Notes"];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"New Blank Sketchbook…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf promptCreateNotebookWithStyle:PDFNotebookTemplateBlank defaultTitle:@"Blank Pad"];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"New Folder…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf promptCreateNewFolder];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"How to Import PDFs…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf showImportHelpAlert];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    ac.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)promptCreateNotebookWithStyle:(PDFNotebookTemplate)style defaultTitle:(NSString *)defaultTitle {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"New Notebook PDF"
                                                                message:@"Enter a notebook title and number of pages:"
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Notebook title";
        tf.text = defaultTitle;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Pages (1 – 200)";
        tf.text = @"20";
        tf.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Create & Open" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(self) sSelf = weakSelf;
        if (!sSelf) return;
        NSString *rawName = [self sanitizeFilename:ac.textFields[0].text];
        if (rawName.length == 0) rawName = defaultTitle;
        NSInteger pages = [ac.textFields[1].text integerValue];
        if (pages <= 0) pages = 20;
        pages = MIN(200, pages);

        NSString *filename = [[rawName.pathExtension lowercaseString] isEqualToString:@"pdf"]
            ? rawName
            : [rawName stringByAppendingPathExtension:@"pdf"];
        NSString *dest = [sSelf uniqueDestinationInDirectory:sSelf->_directoryPath forFilename:filename];

        NSError *err = nil;
        if ([PDFDoc createNotebookPDFAtPath:dest templateStyle:style pageCount:pages error:&err]) {
            [sSelf reloadFiles];
            [sSelf openFileAtPath:dest];
        }
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)promptCreateNewFolder {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"New Folder"
                                                                message:@"Enter a name for the new folder:"
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Folder name";
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(self) sSelf = weakSelf;
        if (!sSelf) return;
        NSString *folderName = [sSelf sanitizeFilename:ac.textFields.firstObject.text];
        if (folderName.length == 0) return;
        if (PDFLibraryNameIsReserved(folderName)) {
            [sSelf showReservedNameAlert];
            return;
        }
        NSString *target = [sSelf->_directoryPath stringByAppendingPathComponent:folderName];
        [[NSFileManager defaultManager] createDirectoryAtPath:target withIntermediateDirectories:NO attributes:nil error:NULL];
        [sSelf reloadFiles];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)showReservedNameAlert {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Reserved Name"
                                                                message:@"Please choose a different name. Inbox and Annotations are reserved for the app."
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)showImportHelpAlert {
    NSString *msg = @"1. Safari / Mail / Cloud Apps: Open any PDF, tap Share, and choose \"Copy to PDF Notes\".\n\n"
                    @"2. iTunes / Finder File Sharing: Connect your iPad over USB, select PDF Notes under File Sharing, and drag PDFs or folders in.\n\n"
                    @"3. Filza (Jailbroken iOS 9): Copy PDFs directly into the app's Documents directory or tap \"Open in PDF Notes\".";
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Importing PDFs on iOS 9"
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Got It" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (NSString *)sanitizeFilename:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSCharacterSet *illegal = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*"];
    return [[trimmed componentsSeparatedByCharactersInSet:illegal] componentsJoinedByString:@"-"];
}

#pragma mark - UITableView DataSource & Async Thumbnails

+ (NSString *)formatFileSize:(unsigned long long)bytes {
    if (bytes < 1024ULL) return [NSString stringWithFormat:@"%llu B", bytes];
    if (bytes < 1024ULL * 1024ULL) return [NSString stringWithFormat:@"%.1f KB", (double)bytes / 1024.0];
    return [NSString stringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_filteredItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PDFLibraryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LibCell" forIndexPath:indexPath];
    PDFLibraryItem *item = _filteredItems[(NSUInteger)indexPath.row];
    cell.representedPath = item.fullPath;
    cell.titleLbl.text = item.name;

    if (item.isDirectory) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.badgeLbl.hidden = YES;
        cell.coverView.backgroundColor = [UIColor clearColor];
        cell.coverView.layer.borderWidth = 0.0f;
        cell.coverView.image = PDFIconFolder();
        cell.coverView.tintColor = [UIColor colorWithRed:0.20f green:0.54f blue:0.96f alpha:1.0f];

        NSArray *sub = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:item.fullPath error:NULL];
        NSUInteger visibleCount = 0;
        for (NSString *s in sub) {
            if (![s hasPrefix:@"."]) visibleCount++;
        }
        cell.metaLbl.text = [NSString stringWithFormat:@"%lu item%@", (unsigned long)visibleCount, visibleCount == 1 ? @"" : @"s"];
        return cell;
    }

    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.coverView.backgroundColor = [UIColor whiteColor];
    cell.coverView.layer.borderWidth = 0.8f;
    cell.coverView.layer.borderColor = [UIColor colorWithWhite:0.80f alpha:1.0f].CGColor;
    cell.coverView.tintColor = nil;

    if (item.hasAnnotations) {
        cell.badgeLbl.text = @"Annotated";
        cell.badgeLbl.hidden = NO;
    } else {
        cell.badgeLbl.hidden = YES;
    }

    NSMutableArray<NSString *> *metaParts = [NSMutableArray array];
    if (item.relativeFolder.length > 0) {
        [metaParts addObject:item.relativeFolder];
    }
    if (item.cachedPageCount > 0) {
        [metaParts addObject:[NSString stringWithFormat:@"%ld p.", (long)item.cachedPageCount]];
    }
    [metaParts addObject:[[self class] formatFileSize:item.fileSize]];
    if (item.lastPage > 0) {
        [metaParts addObject:[NSString stringWithFormat:@"At p. %ld", (long)(item.lastPage + 1)]];
    }
    cell.metaLbl.text = [metaParts componentsJoinedByString:@" · "];
    [cell setNeedsLayout];

    UIImage *cachedThumb = [_coverCache objectForKey:item.fullPath];
    if (cachedThumb) {
        cell.coverView.image = cachedThumb;
    } else {
        cell.coverView.image = nil;
        NSString *path = item.fullPath;
        NSCache *cache = _coverCache;
        CGFloat scale = [UIScreen mainScreen].scale;
        __weak typeof(self) weakSelf = self;
        __weak PDFLibraryCell *weakCell = cell;

        dispatch_async([PDFDoc utilityQueue], ^{
            @autoreleasepool {
                PDFDoc *doc = [[PDFDoc alloc] initWithPath:path];
                NSInteger pCount = doc.pageCount;
                UIImage *thumb = (pCount > 0) ? [doc renderThumbnailAtIndex:0 maxPixelSide:60.0f * scale] : nil;
                if (thumb) [cache setObject:thumb forKey:path
                                      cost:CGImageGetBytesPerRow(thumb.CGImage) * CGImageGetHeight(thumb.CGImage)];

                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(self) sSelf = weakSelf;
                    if (sSelf && pCount > 0) {
                        sSelf->_pageCountCache[path] = @(pCount);
                        item.cachedPageCount = pCount;
                    }
                    PDFLibraryCell *sCell = weakCell;
                    if (sCell && [sCell.representedPath isEqualToString:path]) {
                        sCell.coverView.image = thumb;
                        if (pCount > 0) {
                            NSMutableArray<NSString *> *updated = [NSMutableArray array];
                            if (item.relativeFolder.length > 0) [updated addObject:item.relativeFolder];
                            [updated addObject:[NSString stringWithFormat:@"%ld p.", (long)pCount]];
                            [updated addObject:[[sSelf class] formatFileSize:item.fileSize]];
                            if (item.lastPage > 0) [updated addObject:[NSString stringWithFormat:@"At p. %ld", (long)(item.lastPage + 1)]];
                            sCell.metaLbl.text = [updated componentsJoinedByString:@" · "];
                        }
                    }
                });
            }
        });
    }

    return cell;
}

#pragma mark - Row Selection, Swipe Actions & Context Menu

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [_searchBar resignFirstResponder];

    PDFLibraryItem *item = _filteredItems[(NSUInteger)indexPath.row];
    if (item.isDirectory) {
        LibraryViewController *sub = [[LibraryViewController alloc] initWithDirectory:item.fullPath];
        [self.navigationController pushViewController:sub animated:YES];
    } else {
        [self openFileAtPath:item.fullPath];
    }
}

- (void)openFileAtPath:(NSString *)pdfPath {
    if (pdfPath.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:pdfPath]) return;
    ReaderViewController *reader = [[ReaderViewController alloc] initWithPath:pdfPath];
    [self.navigationController pushViewController:reader animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (NSArray<UITableViewRowAction *> *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    PDFLibraryItem *item = _filteredItems[(NSUInteger)indexPath.row];
    __weak typeof(self) weakSelf = self;

    UITableViewRowAction *del = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleDestructive
                                                                   title:@"Delete"
                                                                 handler:^(UITableViewRowAction *action, NSIndexPath *ip) {
        [weakSelf confirmDeleteItem:item];
    }];

    UITableViewRowAction *ren = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal
                                                                   title:@"Rename"
                                                                 handler:^(UITableViewRowAction *action, NSIndexPath *ip) {
        [tableView setEditing:NO animated:YES];
        [weakSelf promptRenameItem:item];
    }];
    ren.backgroundColor = [UIColor colorWithRed:0.20f green:0.54f blue:0.96f alpha:1.0f];

    if (!item.isDirectory) {
        UITableViewRowAction *mov = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal
                                                                       title:@"Move"
                                                                     handler:^(UITableViewRowAction *action, NSIndexPath *ip) {
            [tableView setEditing:NO animated:YES];
            [weakSelf promptMoveItem:item sourceRect:[tableView rectForRowAtIndexPath:ip]];
        }];
        mov.backgroundColor = [UIColor colorWithRed:0.52f green:0.54f blue:0.60f alpha:1.0f];
        return @[ del, mov, ren ];
    }
    return @[ del, ren ];
}

- (void)handleRowLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    CGPoint pt = [gr locationInView:_tableView];
    NSIndexPath *ip = [_tableView indexPathForRowAtPoint:pt];
    if (!ip) return;

    PDFLibraryItem *item = _filteredItems[(NSUInteger)ip.row];
    CGRect rowRect = [_tableView rectForRowAtIndexPath:ip];

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:item.name
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Rename…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [weakSelf promptRenameItem:item];
    }]];
    if (!item.isDirectory) {
        [ac addAction:[UIAlertAction actionWithTitle:@"Move to Folder…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [weakSelf promptMoveItem:item sourceRect:rowRect];
        }]];
        [ac addAction:[UIAlertAction actionWithTitle:@"Duplicate PDF" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [weakSelf duplicatePDFItem:item];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [weakSelf confirmDeleteItem:item];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *pop = ac.popoverPresentationController;
    if (pop) {
        pop.sourceView = _tableView;
        pop.sourceRect = rowRect;
    }
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)confirmDeleteItem:(PDFLibraryItem *)item {
    NSString *msg = item.isDirectory
        ? @"This folder, all PDFs inside it, and their annotations will be permanently deleted."
        : @"This PDF and its annotations will be permanently deleted.";
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Delete \"%@\"?", item.name]
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        __strong typeof(self) sSelf = weakSelf;
        if (!sSelf) return;
        [AnnotationStore deleteAnnotationsForPath:item.fullPath isDirectory:item.isDirectory];
        [[NSFileManager defaultManager] removeItemAtPath:item.fullPath error:NULL];
        [sSelf->_coverCache removeObjectForKey:item.fullPath];
        [sSelf->_pageCountCache removeObjectForKey:item.fullPath];
        [sSelf reloadFiles];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)promptRenameItem:(PDFLibraryItem *)item {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Rename"
                                                                message:@"Annotations & bookmarks will stay attached automatically."
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = item.name;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Rename" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(self) sSelf = weakSelf;
        if (!sSelf) return;
        NSString *clean = [sSelf sanitizeFilename:ac.textFields.firstObject.text];
        if (clean.length == 0) return;

        NSString *parent = [item.fullPath stringByDeletingLastPathComponent];
        NSString *newFilename = item.isDirectory
            ? clean
            : ([[clean.pathExtension lowercaseString] isEqualToString:@"pdf"] ? clean : [clean stringByAppendingPathExtension:@"pdf"]);
        if (PDFLibraryRenameNameIsReserved(newFilename, [sSelf isRootLibrary], item.relativeFolder)) {
            [sSelf showReservedNameAlert];
            return;
        }
        NSString *newPath = [parent stringByAppendingPathComponent:newFilename];
        if ([newPath isEqualToString:item.fullPath]) return;

        if ([[NSFileManager defaultManager] fileExistsAtPath:newPath]) {
            UIAlertController *exists = [UIAlertController alertControllerWithTitle:@"Name Already Exists"
                                                                            message:@"Please choose a different name."
                                                                     preferredStyle:UIAlertControllerStyleAlert];
            [exists addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [sSelf presentViewController:exists animated:YES completion:nil];
            return;
        }

        if ([[NSFileManager defaultManager] moveItemAtPath:item.fullPath toPath:newPath error:NULL]) {
            [AnnotationStore moveAnnotationsFromPath:item.fullPath toPath:newPath isDirectory:item.isDirectory];
            [sSelf reloadFiles];
        }
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)collectFoldersUnder:(NSString *)dir relative:(NSString *)rel into:(NSMutableArray<NSDictionary *> *)outFolders {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:dir error:NULL];
    NSString *docs = [AnnotationStore documentsDirectory];
    BOOL atRoot = [[dir stringByResolvingSymlinksInPath] isEqualToString:docs];

    for (NSString *n in names) {
        if ([n hasPrefix:@"."]) continue;
        if (atRoot && ([n isEqualToString:@"Inbox"] || [n isEqualToString:@"Annotations"])) continue;
        NSString *full = [dir stringByAppendingPathComponent:n];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir) {
            NSString *disp = rel.length > 0 ? [rel stringByAppendingPathComponent:n] : n;
            [outFolders addObject:@{ @"title": disp, @"path": full }];
            [self collectFoldersUnder:full relative:disp into:outFolders];
        }
    }
}

- (void)promptMoveItem:(PDFLibraryItem *)item sourceRect:(CGRect)sourceRect {
    NSString *docs = [AnnotationStore documentsDirectory];
    NSMutableArray<NSDictionary *> *destinations = [NSMutableArray array];
    NSString *curParent = [[item.fullPath stringByDeletingLastPathComponent] stringByResolvingSymlinksInPath];

    if (![curParent isEqualToString:docs]) {
        [destinations addObject:@{ @"title": @"Library Root (Documents)", @"path": docs }];
    }
    [self collectFoldersUnder:docs relative:@"" into:destinations];

    NSMutableArray<NSDictionary *> *validDests = [NSMutableArray array];
    for (NSDictionary *d in destinations) {
        NSString *p = [d[@"path"] stringByResolvingSymlinksInPath];
        if (![p isEqualToString:curParent]) {
            [validDests addObject:d];
        }
    }

    if (validDests.count == 0) {
        UIAlertController *info = [UIAlertController alertControllerWithTitle:@"No Other Folders"
                                                                      message:@"Create a folder first using the + button at the top right."
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [info addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:info animated:YES completion:nil];
        return;
    }

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Move \"%@\"", item.name]
                                                                message:@"Choose destination folder:"
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *dest in validDests) {
        [ac addAction:[UIAlertAction actionWithTitle:dest[@"title"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            __strong typeof(self) sSelf = weakSelf;
            if (!sSelf) return;
            NSString *targetDir = dest[@"path"];
            NSString *newPath = [sSelf uniqueDestinationInDirectory:targetDir forFilename:[item.fullPath lastPathComponent]];
            if ([[NSFileManager defaultManager] moveItemAtPath:item.fullPath toPath:newPath error:NULL]) {
                [AnnotationStore moveAnnotationsFromPath:item.fullPath toPath:newPath isDirectory:NO];
                [sSelf reloadFiles];
            }
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *pop = ac.popoverPresentationController;
    if (pop) {
        pop.sourceView = _tableView;
        pop.sourceRect = sourceRect;
    }
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)duplicatePDFItem:(PDFLibraryItem *)item {
    NSString *parent = [item.fullPath stringByDeletingLastPathComponent];
    NSString *copyName = [NSString stringWithFormat:@"%@-Copy.pdf", item.name];
    NSString *dest = [self uniqueDestinationInDirectory:parent forFilename:copyName];
    if ([[NSFileManager defaultManager] copyItemAtPath:item.fullPath toPath:dest error:NULL]) {
        NSString *oldAnn = [AnnotationStore annotationFilePathForPDFPath:item.fullPath];
        NSString *newAnn = [AnnotationStore annotationFilePathForPDFPath:dest];
        if ([[NSFileManager defaultManager] fileExistsAtPath:oldAnn]) {
            [[NSFileManager defaultManager] copyItemAtPath:oldAnn toPath:newAnn error:NULL];
        }
        [self reloadFiles];
    }
}

@end
