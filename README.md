# PDF Notes v3.2 (iPad 3 / iOS 9.3.6 Edition)

Lightweight, native Objective-C PDF reader, handwritten annotator, and notebook app engineered specifically for **iPad 3 (`armv7` 32-bit, A5X SoC, 2048×1536 Retina display, 1 GB RAM) running iOS 9.0–9.3.6**.

In the library, swipe left on a PDF or notebook and tap **Favorite**, or long-press it and choose **Add to Favorites**. Tap **Favorites** at the library root to search and sort starred documents from all folders; tap **All Items** to return. Renaming or moving a document in the app keeps its star. Duplicates start unstarred.

## Project Structure

- `src/Models.h`, `src/Models.m` — `Stroke`, `TextNote`, `AnnotationStore` (single-load per-document store, 45-step Undo/Redo, bookmarks, reading position, atomic XML plist persistence, and library file-move/rename migration), and `PDFWeakTimerTarget`.
- `src/PDFDoc.h`, `src/PDFDoc.m` — Thread-safe `CGPDFDocumentRef` engine, DJB2 margin-trim cache (`PDFNotesTrims`), Paper/Sepia/Night rendering themes, PDF Outline (Table of Contents) parser, `CGPDFScannerRef` text search, streaming vector PDF exporter, and vector notebook PDF generator.
- `src/PageView.h`, `src/PageView.m` — Zoom-aware & theme-aware Retina page view, `kCGBlendModeMultiply` marker ink blending, incremental `O(1)` quadratic Bezier live stroke path, Hold-to-Snap straight line, non-destructive staged segment-to-segment eraser, and draggable sticky notes.
- `src/NavigationSheetController.h`, `src/NavigationSheetController.m` — Modal browser with async cached Page Thumbnails grid, PDF Outline (TOC), and Bookmarked/Annotated pages list.
- `src/ReaderViewController.h`, `src/ReaderViewController.m` — Virtualized reader viewport (`~3–4` active pages in RAM regardless of document length), rotation-safe scroll anchors, responsive floating dock, 9-swatch + rainbow hue & thickness style panel, in-PDF text search bar, and vector export options.
- `src/LibraryViewController.h`, `src/LibraryViewController.m` — Cover thumbnails, live search across folders, sorting, built-in Blank/Ruled/Grid/Dotted/Cornell notebook generator, folder creation, and annotation-preserving Rename/Move/Duplicate/Delete.
- `src/PDFIcons.h`, `src/PDFIcons.m` — 20 CoreGraphics vector template icons.
- `src/AppDelegate.h`, `src/AppDelegate.m`, `src/main.m` — App lifecycle & external `"Copy to PDF Notes"` / `Inbox` import handling.
- `Resources/` — `Info.plist` and app icons.
- `build.sh` — Cross-compiles `armv7-apple-ios9.0` against `iPhoneOS9.3.sdk`, signs with `ldid` (dual SHA-1 + SHA-256 `CodeDirectory`), and packages `PDFNotes.ipa`.

## Building

```bash
./build.sh
```

Output IPA: `PDFNotes.ipa` in the repository root.

## Backward Compatibility

- Bundle Identifier: `com.pdfnotes.ios9` (upgrades cleanly over v2.5 in place).
- Existing `Documents/Annotations/*.plist` (`v1` flat arrays and `v2` page maps) and `Library/Caches/PDFNotesTrims/*.plist` caches load seamlessly without losing a single stroke.
