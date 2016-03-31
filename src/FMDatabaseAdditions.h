//
//  FMDatabaseAdditions.h
//  fmkit
//
//  Created by August Mueller on 10/30/05.
//  Copyright 2005 Flying Meat Inc.. All rights reserved.
//

#import <ObjFW/OFObject.h>
#import "FMDatabase.h"

@class OFString;
@class OFDataArray;
@class OFDate;

@interface FMDatabase (FMDatabaseAdditions)


- (int)intForQuery:(OFString*)objs, ...;
- (long)longForQuery:(OFString*)objs, ...; 
- (BOOL)boolForQuery:(OFString*)objs, ...;
- (double)doubleForQuery:(OFString*)objs, ...;
- (OFString*)stringForQuery:(OFString*)objs, ...; 
- (OFDataArray*)dataForQuery:(OFString*)objs, ...;
- (OFDate*)dateForQuery:(OFString*)objs, ...;

// Notice that there's no dataNoCopyForQuery:.
// That would be a bad idea, because we close out the result set, and then what
// happens to the data that we just didn't copy?  Who knows, not I.


- (BOOL)tableExists:(OFString*)tableName;
- (FMResultSet*)getSchema;
- (FMResultSet*)getTableSchema:(OFString*)tableName;
- (BOOL)columnExists:(OFString*)tableName columnName:(OFString*)columnName;

- (BOOL)validateSQL:(OFString*)sql;

@end
