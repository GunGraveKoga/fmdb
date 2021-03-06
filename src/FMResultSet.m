#import <ObjFW/ObjFW.h>
#import "FMResultSet.h"
#import "FMDatabase.h"
#import "unistd.h"

@interface FMDatabase ()
- (void)resultSetDidClose:(FMResultSet *)resultSet;
@end


@interface FMResultSet (Private)
- (OFMutableDictionary *)columnNameToIndexMap;
- (void)setColumnNameToIndexMap:(OFMutableDictionary *)value;
@end

@implementation FMResultSet

@synthesize query = _query;
@synthesize columnNameToIndexMap = _columnNameToIndexMap;
@synthesize statement = _statement;

+ (id)resultSetWithStatement:(FMStatement *)statement usingParentDatabase:(FMDatabase*)aDB {
    
    FMResultSet *rs = [[FMResultSet alloc] init];
    
    [rs setStatement:statement];
    [rs setParentDB:aDB];
    
    return [rs autorelease];
}

- (void)dealloc {
    [self close];
    
    [_query release];
    _query = nil;
    
    [_columnNameToIndexMap release];
    _columnNameToIndexMap = nil;
    
    [super dealloc];
}

- (void)close {
    [_statement reset];
    [_statement release];
    _statement = nil;
    
    // we don't need this anymore... (i think)
    //[parentDB setInUse:NO];
    [_parentDB resultSetDidClose:self];
    _parentDB = nil;
}

- (int)columnCount {
	return sqlite3_column_count(_statement.statement);
}

- (void)setupColumnNames {
    
    if (!_columnNameToIndexMap) {
        [self setColumnNameToIndexMap:[OFMutableDictionary dictionary]];
    }    
    
    int columnCount = sqlite3_column_count(_statement.statement);
    
    int columnIdx = 0;
    for (columnIdx = 0; columnIdx < columnCount; columnIdx++) {
        [_columnNameToIndexMap setObject:[OFNumber numberWithInt:columnIdx]
                                 forKey:[[OFString stringWithUTF8String:sqlite3_column_name(_statement.statement, columnIdx)] lowercaseString]];
    }
    _columnNamesSetup = YES;
}

- (void)kvcMagic:(id)object {
    
    int columnCount = sqlite3_column_count(_statement.statement);
    
    int columnIdx = 0;
    for (columnIdx = 0; columnIdx < columnCount; columnIdx++) {
        
        const char *c = (const char *)sqlite3_column_text(_statement.statement, columnIdx);
        
        // check for a null row
        if (c) {
            OFString *s = [OFString stringWithUTF8String:c];
            
            [object setValue:s forKey:[OFString stringWithUTF8String:sqlite3_column_name(_statement.statement, columnIdx)]];
        }
    }
}

- (OFDictionary *)resultDict {
    
    int num_cols = sqlite3_data_count(_statement.statement);
    
    if (num_cols > 0) {
        OFMutableDictionary *dict = [OFMutableDictionary dictionaryWithCapacity:num_cols];
        
        if (!_columnNamesSetup) {
            [self setupColumnNames];
        }

        for (OFString* columnName in _columnNameToIndexMap) {
            id objectValue = [self objectForColumnName:columnName];
            [dict setObject:objectValue forKey:columnName];
        }
        
        [dict makeImmutable];

        return dict;
    }
    else {
        of_log(@"Warning: There seem to be no columns in this set.");
    }
    
    return nil;
}

- (BOOL)next {
    
    int rc;
    BOOL retry;
    int numberOfRetries = 0;
    do {
        retry = NO;
        
        rc = sqlite3_step(_statement.statement);
        
        if (SQLITE_BUSY == rc || SQLITE_LOCKED == rc) {
            // this will happen if the db is locked, like if we are doing an update or insert.
            // in that case, retry the step... and maybe wait just 10 milliseconds.
            retry = YES;
            if (SQLITE_LOCKED == rc) {
                rc = sqlite3_reset(_statement.statement);
                if (rc != SQLITE_LOCKED) {
                    of_log(@"Unexpected result from sqlite3_reset (%d) rs", rc);
                }
            }
            [OFThread sleepForTimeInterval:0.00002];
            
            if ([_parentDB busyRetryTimeout] && (numberOfRetries++ > [_parentDB busyRetryTimeout])) {
                
                of_log(@"%s:%d Database busy (%@)", sel_getName(_cmd), __LINE__, [_parentDB databasePath]);
                of_log(@"Database busy");
                break;
            }
        }
        else if (SQLITE_DONE == rc || SQLITE_ROW == rc) {
            // all is well, let's return.
        }
        else if (SQLITE_ERROR == rc) {
            of_log(@"Error calling sqlite3_step (%d: %s) rs", rc, sqlite3_errmsg([_parentDB sqliteHandle]));
            break;
        } 
        else if (SQLITE_MISUSE == rc) {
            // uh oh.
            of_log(@"Error calling sqlite3_step (%d: %s) rs", rc, sqlite3_errmsg([_parentDB sqliteHandle]));
            break;
        }
        else {
            // wtf?
            of_log(@"Unknown error calling sqlite3_step (%d: %s) rs", rc, sqlite3_errmsg([_parentDB sqliteHandle]));
            break;
        }
        
    } while (retry);
    
    
    if (rc != SQLITE_ROW) {
        [self close];
    }
    
    return (rc == SQLITE_ROW);
}

- (BOOL)hasAnotherRow {
    return sqlite3_errcode([_parentDB sqliteHandle]) == SQLITE_ROW;
}

- (int)columnIndexForName:(OFString*)columnName {
    
    if (!_columnNamesSetup) {
        [self setupColumnNames];
    }
    
    columnName = [columnName lowercaseString];
    
    OFNumber *n = [_columnNameToIndexMap objectForKey:columnName];
    
    if (n) {
        return [n intValue];
    }
    
    of_log(@"Warning: I could not find the column named '%@'.", columnName);
    
    return -1;
}



- (int)intForColumn:(OFString*)columnName {
    return [self intForColumnIndex:[self columnIndexForName:columnName]];
}

- (int)intForColumnIndex:(int)columnIdx {
    return sqlite3_column_int(_statement.statement, columnIdx);
}

- (long)longForColumn:(OFString*)columnName {
    return [self longForColumnIndex:[self columnIndexForName:columnName]];
}

- (long)longForColumnIndex:(int)columnIdx {
    return (long)sqlite3_column_int64(_statement.statement, columnIdx);
}

- (long long int)longLongIntForColumn:(OFString*)columnName {
    return [self longLongIntForColumnIndex:[self columnIndexForName:columnName]];
}

- (long long int)longLongIntForColumnIndex:(int)columnIdx {
    return sqlite3_column_int64(_statement.statement, columnIdx);
}

- (BOOL)boolForColumn:(OFString*)columnName {
    return [self boolForColumnIndex:[self columnIndexForName:columnName]];
}

- (BOOL)boolForColumnIndex:(int)columnIdx {
    return ([self intForColumnIndex:columnIdx] != 0);
}

- (double)doubleForColumn:(OFString*)columnName {
    return [self doubleForColumnIndex:[self columnIndexForName:columnName]];
}

- (double)doubleForColumnIndex:(int)columnIdx {
    return sqlite3_column_double(_statement.statement, columnIdx);
}

- (OFString*)stringForColumnIndex:(int)columnIdx {
    
    if (sqlite3_column_type(_statement.statement, columnIdx) == SQLITE_NULL || (columnIdx < 0)) {
        return nil;
    }
    
    const char *c = (const char *)sqlite3_column_text(_statement.statement, columnIdx);
    
    if (!c) {
        // null row.
        return nil;
    }
    
    return [OFString stringWithUTF8String:c];
}

- (OFString*)stringForColumn:(OFString*)columnName {
    return [self stringForColumnIndex:[self columnIndexForName:columnName]];
}

- (OFDate*)dateForColumn:(OFString*)columnName {
    return [self dateForColumnIndex:[self columnIndexForName:columnName]];
}

- (OFDate*)dateForColumnIndex:(int)columnIdx {
    
    if (sqlite3_column_type(_statement.statement, columnIdx) == SQLITE_NULL || (columnIdx < 0)) {
        return nil;
    }
    
    return [OFDate dateWithTimeIntervalSince1970:[self doubleForColumnIndex:columnIdx]];
}


- (OFDataArray*)dataForColumn:(OFString*)columnName {
    return [self dataForColumnIndex:[self columnIndexForName:columnName]];
}

- (OFDataArray*)dataForColumnIndex:(int)columnIdx {
    
    if (sqlite3_column_type(_statement.statement, columnIdx) == SQLITE_NULL || (columnIdx < 0)) {
        return nil;
    }
    
    int dataSize = sqlite3_column_bytes(_statement.statement, columnIdx);
    
    OFDataArray *data = [OFDataArray dataArrayWithCapacity:dataSize];
    void* buf = __builtin_alloca(dataSize);
    
    memcpy(buf, sqlite3_column_blob(_statement.statement, columnIdx), dataSize);

    [data addItems:buf count:dataSize];
    
    return data;
}


- (OFDataArray*)dataNoCopyForColumn:(OFString*)columnName {
    return [self dataNoCopyForColumnIndex:[self columnIndexForName:columnName]];
}

- (OFDataArray*)dataNoCopyForColumnIndex:(int)columnIdx {
    
    if (sqlite3_column_type(_statement.statement, columnIdx) == SQLITE_NULL || (columnIdx < 0)) {
        return nil;
    }
    
    int dataSize = sqlite3_column_bytes(_statement.statement, columnIdx);
    
    void* buf = (void *)sqlite3_column_blob(_statement.statement, columnIdx);

    OFDataArray *data = [OFDataArray dataArrayWithCapacity:dataSize];

    [data addItems:buf count:dataSize];
    
    return data;
}


- (BOOL)columnIndexIsNull:(int)columnIdx {
    return sqlite3_column_type(_statement.statement, columnIdx) == SQLITE_NULL;
}

- (BOOL)columnIsNull:(OFString*)columnName {
    return [self columnIndexIsNull:[self columnIndexForName:columnName]];
}

- (const unsigned char *)UTF8StringForColumnIndex:(int)columnIdx {
    
    if (sqlite3_column_type(_statement.statement, columnIdx) == SQLITE_NULL || (columnIdx < 0)) {
        return NULL;
    }
    
    return sqlite3_column_text(_statement.statement, columnIdx);
}

- (const unsigned char *)UTF8StringForColumnName:(OFString*)columnName {
    return [self UTF8StringForColumnIndex:[self columnIndexForName:columnName]];
}

- (id)objectForColumnIndex:(int)columnIdx {
    int columnType = sqlite3_column_type(_statement.statement, columnIdx);
    
    id returnValue = nil;
    
    if (columnType == SQLITE_INTEGER) {
        returnValue = [OFNumber numberWithLongLong:[self longLongIntForColumnIndex:columnIdx]];
    }
    else if (columnType == SQLITE_FLOAT) {
        returnValue = [OFNumber numberWithDouble:[self doubleForColumnIndex:columnIdx]];
    }
    else if (columnType == SQLITE_BLOB) {
        returnValue = [self dataForColumnIndex:columnIdx];
    }
    else {
        //default to a string for everything else
        returnValue = [self stringForColumnIndex:columnIdx];
    }
    
    if (returnValue == nil) {
        returnValue = [OFNull null];
    }
    
    return returnValue;
}

- (id)objectForColumnName:(OFString*)columnName {
    return [self objectForColumnIndex:[self columnIndexForName:columnName]];
}

// returns autoreleased OFString containing the name of the column in the result set
- (OFString*)columnNameForIndex:(int)columnIdx {
    return [OFString stringWithUTF8String: sqlite3_column_name(_statement.statement, columnIdx)];
}

- (void)setParentDB:(FMDatabase *)newDb {
    _parentDB = newDb;
}


@end
