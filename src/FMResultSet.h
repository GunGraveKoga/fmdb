#import <ObjFW/OFObject.h>
#import "sqlite3.h"

#ifndef __has_feature      // Optional.
#define __has_feature(x) 0 // Compatibility with non-clang compilers.
#endif

#ifndef NS_RETURNS_NOT_RETAINED
#if __has_feature(attribute_ns_returns_not_retained)
#define NS_RETURNS_NOT_RETAINED __attribute__((ns_returns_not_retained))
#else
#define NS_RETURNS_NOT_RETAINED
#endif
#endif

@class OFMutableDictionary;
@class OFString;
@class OFDate;
@class OFDataArray;
@class OFDictionary;
@class FMDatabase;
@class FMStatement;

@interface FMResultSet : OFObject {
    FMDatabase *_parentDB;
    FMStatement *_statement;
    
    OFString *_query;
    OFMutableDictionary *_columnNameToIndexMap;
    BOOL _columnNamesSetup;
}

@property (retain) OFString *query;
@property (retain) OFMutableDictionary *columnNameToIndexMap;
@property (retain) FMStatement *statement;

+ (id)resultSetWithStatement:(FMStatement *)statement usingParentDatabase:(FMDatabase*)aDB;

- (void)close;

- (void)setParentDB:(FMDatabase *)newDb;

- (BOOL)next;
- (BOOL)hasAnotherRow;

- (int)columnCount;

- (int)columnIndexForName:(OFString*)columnName;
- (OFString*)columnNameForIndex:(int)columnIdx;

- (int)intForColumn:(OFString*)columnName;
- (int)intForColumnIndex:(int)columnIdx;

- (long)longForColumn:(OFString*)columnName;
- (long)longForColumnIndex:(int)columnIdx;

- (long long int)longLongIntForColumn:(OFString*)columnName;
- (long long int)longLongIntForColumnIndex:(int)columnIdx;

- (BOOL)boolForColumn:(OFString*)columnName;
- (BOOL)boolForColumnIndex:(int)columnIdx;

- (double)doubleForColumn:(OFString*)columnName;
- (double)doubleForColumnIndex:(int)columnIdx;

- (OFString*)stringForColumn:(OFString*)columnName;
- (OFString*)stringForColumnIndex:(int)columnIdx;

- (OFDate*)dateForColumn:(OFString*)columnName;
- (OFDate*)dateForColumnIndex:(int)columnIdx;

- (OFDataArray*)dataForColumn:(OFString*)columnName;
- (OFDataArray*)dataForColumnIndex:(int)columnIdx;

- (const unsigned char *)UTF8StringForColumnIndex:(int)columnIdx;
- (const unsigned char *)UTF8StringForColumnName:(OFString*)columnName;

// returns one of NSNumber, OFString, OFDataArray, or NSNull
- (id)objectForColumnName:(OFString*)columnName;
- (id)objectForColumnIndex:(int)columnIdx;

/*
If you are going to use this data after you iterate over the next row, or after you close the
result set, make sure to make a copy of the data first (or just use dataForColumn:/dataForColumnIndex:)
If you don't, you're going to be in a world of hurt when you try and use the data.
*/
- (OFDataArray*)dataNoCopyForColumn:(OFString*)columnName NS_RETURNS_NOT_RETAINED;
- (OFDataArray*)dataNoCopyForColumnIndex:(int)columnIdx NS_RETURNS_NOT_RETAINED;

- (BOOL)columnIndexIsNull:(int)columnIdx;
- (BOOL)columnIsNull:(OFString*)columnName;

- (void)kvcMagic:(id)object;
- (OFDictionary *)resultDict;

@end
