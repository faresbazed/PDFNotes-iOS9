#import "NavigationSheetController.h"
#import "PDFIcons.h"

@interface PDFThumbCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *thumbImageView;
@property (nonatomic, strong) UILabel *pageLabel;
@property (nonatomic, strong) UIView *inkDot;
@property (nonatomic, strong) UIImageView *bookmarkIcon;
@property (nonatomic, strong) PDFCancelToken *renderToken;
@property (nonatomic, assign) NSInteger representedPage;
@end

@implementation PDFThumbCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = [UIColor clearColor];

        _thumbImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _thumbImageView.backgroundColor = [UIColor whiteColor];
        _thumbImageView.contentMode = UIViewContentModeScaleAspectFit;
        _thumbImageView.clipsToBounds = YES;
        _thumbImageView.layer.cornerRadius = 4.0f;
        _thumbImageView.layer.borderWidth = 1.0f;
        _thumbImageView.layer.borderColor = [UIColor colorWithWhite:0.78f alpha:1.0f].CGColor;
        [self.contentView addSubview:_thumbImageView];

        _bookmarkIcon = [[UIImageView alloc] initWithImage:PDFIconBookmark(YES)];
        _bookmarkIcon.tintColor = [UIColor colorWithRed:0.92f green:0.26f blue:0.24f alpha:1.0f];
        _bookmarkIcon.hidden = YES;
        [self.contentView addSubview:_bookmarkIcon];

        _pageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _pageLabel.font = [UIFont boldSystemFontOfSize:12.0f];
        _pageLabel.textAlignment = NSTextAlignmentCenter;
        _pageLabel.textColor = [UIColor colorWithWhite:0.22f alpha:1.0f];
        [self.contentView addSubview:_pageLabel];

        _inkDot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 7, 7)];
        _inkDot.backgroundColor = [UIColor colorWithRed:0.16f green:0.50f blue:0.96f alpha:1.0f];
        _inkDot.layer.cornerRadius = 3.5f;
        _inkDot.hidden = YES;
        [self.contentView addSubview:_inkDot];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [_renderToken cancel];
    _renderToken = nil;
    _thumbImageView.image = nil;
    _bookmarkIcon.hidden = YES;
    _inkDot.hidden = YES;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize sz = self.contentView.bounds.size;
    CGFloat labelH = 22.0f;
    _thumbImageView.frame = CGRectMake(4.0f, 4.0f, sz.width - 8.0f, sz.height - labelH - 6.0f);
    _bookmarkIcon.frame = CGRectMake(CGRectGetMaxX(_thumbImageView.frame) - 20.0f, 3.0f, 16.0f, 16.0f);
    _pageLabel.frame = CGRectMake(0.0f, sz.height - labelH, sz.width, labelH);
    [_pageLabel sizeToFit];
    CGFloat lw = _pageLabel.bounds.size.width;
    CGFloat totalW = _inkDot.hidden ? lw : (lw + 11.0f);
    CGFloat startX = floorf((float)((sz.width - totalW) * 0.5f));
    _pageLabel.frame = CGRectMake(startX, sz.height - labelH + 2.0f, lw, 18.0f);
    _inkDot.frame = CGRectMake(CGRectGetMaxX(_pageLabel.frame) + 4.0f, sz.height - labelH + 7.5f, 7.0f, 7.0f);
}

@end

#pragma mark - NavigationSheetController

@interface NavigationSheetController () <UICollectionViewDataSource, UICollectionViewDelegate, UITableViewDataSource, UITableViewDelegate>
@end

@implementation NavigationSheetController {
    PDFDoc *_doc;
    AnnotationStore *_store;
    NSInteger _currentPage;

    UISegmentedControl *_modeControl;
    UICollectionView *_collectionView;
    UITableView *_tableView;
    UILabel *_emptyLabel;

    NSArray<PDFOutlineItem *> *_outlineItems;
    NSMutableArray<NSNumber *> *_savedPages; // Union of bookmarked + annotated pages
    NSCache *_thumbCache;
    BOOL _didInitialScroll;
}

- (instancetype)initWithDoc:(PDFDoc *)doc
                      store:(AnnotationStore *)store
                currentPage:(NSInteger)currentPage {
    self = [super init];
    if (self) {
        _doc = doc;
        _store = store;
        _currentPage = currentPage;
        _thumbCache = [[NSCache alloc] init];
        _thumbCache.countLimit = 48;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.95f green:0.95f blue:0.97f alpha:1.0f];

    _outlineItems = [_doc outlineItems] ?: @[];
    [self rebuildSavedPagesList];

    _modeControl = [[UISegmentedControl alloc] initWithItems:@[ @"Pages", @"Outline", @"Saved" ]];
    _modeControl.selectedSegmentIndex = 0;
    [_modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _modeControl;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                           target:self
                                                                                           action:@selector(closeTapped)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Go to…"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(jumpToPageTapped)];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(124.0f, 174.0f);
    layout.minimumInteritemSpacing = 12.0f;
    layout.minimumLineSpacing = 16.0f;
    layout.sectionInset = UIEdgeInsetsMake(16.0f, 16.0f, 20.0f, 16.0f);

    _collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    _collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _collectionView.backgroundColor = self.view.backgroundColor;
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    [_collectionView registerClass:[PDFThumbCell class] forCellWithReuseIdentifier:@"ThumbCell"];
    [self.view addSubview:_collectionView];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.hidden = YES;
    _tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:_tableView];

    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 32.0f, 32.0f)];
    _emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.font = [UIFont systemFontOfSize:15.0f];
    _emptyLabel.textColor = [UIColor colorWithWhite:0.48f alpha:1.0f];
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!_didInitialScroll && _doc.pageCount > 0 && _currentPage >= 0 && _currentPage < _doc.pageCount) {
        _didInitialScroll = YES;
        NSIndexPath *ip = [NSIndexPath indexPathForItem:_currentPage inSection:0];
        [_collectionView scrollToItemAtIndexPath:ip atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:NO];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [_thumbCache removeAllObjects];
}

- (void)rebuildSavedPagesList {
    NSMutableIndexSet *combined = [NSMutableIndexSet indexSet];
    [combined addIndexes:[_store bookmarkedPages]];
    [combined addIndexes:[_store annotatedPages]];
    _savedPages = [NSMutableArray array];
    [combined enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        if ((NSInteger)idx < _doc.pageCount) {
            [_savedPages addObject:@(idx)];
        }
    }];
}

- (void)modeChanged:(UISegmentedControl *)seg {
    NSInteger idx = seg.selectedSegmentIndex;
    _collectionView.hidden = (idx != 0);
    _tableView.hidden = (idx == 0);

    if (idx == 1) {
        _emptyLabel.hidden = (_outlineItems.count > 0);
        _emptyLabel.text = @"This PDF does not contain an embedded Table of Contents.";
        [_tableView reloadData];
    } else if (idx == 2) {
        [self rebuildSavedPagesList];
        _emptyLabel.hidden = (_savedPages.count > 0);
        _emptyLabel.text = @"No bookmarked or annotated pages yet.\n\nTap the bookmark icon in the reader or draw on any page to see it listed here.";
        [_tableView reloadData];
    } else {
        _emptyLabel.hidden = YES;
    }
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)jumpToPageTapped {
    if (_doc.pageCount <= 0) return;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Go to Page"
                                                                message:[NSString stringWithFormat:@"Enter a page number (1 – %ld):", (long)_doc.pageCount]
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.placeholder = [NSString stringWithFormat:@"%ld", (long)(_currentPage + 1)];
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Go" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(self) sSelf = weakSelf;
        if (!sSelf) return;
        NSInteger entered = [ac.textFields.firstObject.text integerValue];
        if (entered >= 1 && entered <= sSelf->_doc.pageCount) {
            [sSelf selectPageAndDismiss:entered - 1];
        }
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)selectPageAndDismiss:(NSInteger)pageIndex {
    void (^cb)(NSInteger) = self.onSelectPage;
    [self dismissViewControllerAnimated:YES completion:^{
        if (cb) cb(pageIndex);
    }];
}

#pragma mark - UICollectionView (Thumbnails)

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return _doc.pageCount;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    PDFThumbCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"ThumbCell" forIndexPath:indexPath];
    NSInteger page = indexPath.item;
    cell.representedPage = page;
    cell.pageLabel.text = [NSString stringWithFormat:@"%ld", (long)(page + 1)];
    cell.inkDot.hidden = ![_store hasAnnotationsOnPage:page];
    cell.bookmarkIcon.hidden = ![_store isPageBookmarked:page];
    [cell setNeedsLayout];

    if (page == _currentPage) {
        cell.thumbImageView.layer.borderWidth = 2.5f;
        cell.thumbImageView.layer.borderColor = [UIColor colorWithRed:0.14f green:0.48f blue:0.96f alpha:1.0f].CGColor;
        cell.pageLabel.textColor = [UIColor colorWithRed:0.12f green:0.44f blue:0.92f alpha:1.0f];
    } else {
        cell.thumbImageView.layer.borderWidth = 1.0f;
        cell.thumbImageView.layer.borderColor = [UIColor colorWithWhite:0.78f alpha:1.0f].CGColor;
        cell.pageLabel.textColor = [UIColor colorWithWhite:0.22f alpha:1.0f];
    }

    UIImage *cached = [_thumbCache objectForKey:@(page)];
    if (cached) {
        cell.thumbImageView.image = cached;
    } else {
        PDFCancelToken *token = [[PDFCancelToken alloc] init];
        cell.renderToken = token;
        PDFDoc *doc = _doc;
        NSCache *cache = _thumbCache;
        CGFloat scale = [UIScreen mainScreen].scale;
        __weak PDFThumbCell *weakCell = cell;

        dispatch_async([PDFDoc utilityQueue], ^{
            if (token.isCancelled) return;
            UIImage *img = [doc renderThumbnailAtIndex:page maxPixelSide:150.0f * scale];
            if (!img || token.isCancelled) return;
            [cache setObject:img forKey:@(page)];

            dispatch_async(dispatch_get_main_queue(), ^{
                PDFThumbCell *sCell = weakCell;
                if (!sCell || sCell.representedPage != page || token.isCancelled) return;
                sCell.thumbImageView.image = img;
            });
        });
    }
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [self selectPageAndDismiss:indexPath.item];
}

#pragma mark - UITableView (Outline & Saved Pages)

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (_modeControl.selectedSegmentIndex == 1) {
        return (NSInteger)_outlineItems.count;
    }
    return (NSInteger)_savedPages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const kCellID = @"NavRow";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kCellID];
    }

    if (_modeControl.selectedSegmentIndex == 1) {
        PDFOutlineItem *item = _outlineItems[(NSUInteger)indexPath.row];
        NSString *indent = [@"" stringByPaddingToLength:(NSUInteger)(item.level * 3) withString:@" " startingAtIndex:0];
        cell.textLabel.text = [indent stringByAppendingString:item.title];
        cell.textLabel.font = (item.level == 0) ? [UIFont boldSystemFontOfSize:15.0f] : [UIFont systemFontOfSize:14.0f];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"p. %ld", (long)(item.pageIndex + 1)];
        cell.imageView.image = nil;
    } else {
        NSInteger page = [_savedPages[(NSUInteger)indexPath.row] integerValue];
        BOOL bm = [_store isPageBookmarked:page];
        BOOL ann = [_store hasAnnotationsOnPage:page];
        NSUInteger strokeCount = [_store strokesForPage:page].count;
        NSUInteger noteCount = [_store notesForPage:page].count;

        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0f];
        cell.textLabel.text = [NSString stringWithFormat:@"Page %ld", (long)(page + 1)];

        NSMutableArray *tags = [NSMutableArray array];
        if (bm) [tags addObject:@"Bookmarked"];
        if (strokeCount > 0) [tags addObject:[NSString stringWithFormat:@"%lu stroke%@", (unsigned long)strokeCount, strokeCount == 1 ? @"" : @"s"]];
        if (noteCount > 0) [tags addObject:[NSString stringWithFormat:@"%lu note%@", (unsigned long)noteCount, noteCount == 1 ? @"" : @"s"]];
        else if (ann && strokeCount == 0) [tags addObject:@"Annotated"];
        cell.detailTextLabel.text = [tags componentsJoinedByString:@" · "];

        cell.imageView.image = bm ? PDFIconBookmark(YES) : PDFIconPen();
        cell.imageView.tintColor = bm
            ? [UIColor colorWithRed:0.92f green:0.26f blue:0.24f alpha:1.0f]
            : [UIColor colorWithRed:0.16f green:0.50f blue:0.96f alpha:1.0f];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_modeControl.selectedSegmentIndex == 1) {
        PDFOutlineItem *item = _outlineItems[(NSUInteger)indexPath.row];
        [self selectPageAndDismiss:item.pageIndex];
    } else {
        NSInteger page = [_savedPages[(NSUInteger)indexPath.row] integerValue];
        [self selectPageAndDismiss:page];
    }
}

@end
