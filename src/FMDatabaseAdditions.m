//
//  FMDatabaseAdditions.m
//  fmkit
//
//  Created by August Mueller on 10/30/05.
//  Copyright 2005 Flying Meat Inc.. All rights reserved.
//
#import <ObjFW/ObjFW.h>
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"

@implementation FMDatabase (FMDatabaseAdditions)

#define RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(type, sel)             \
va_list args;                                                        \
va_start(args, query);                                               \
FMResultSet *resultSet = [self executeQuery:query withArgumentsInArray:0x00 orVAList:args];   \
va_end(args);                                                        \
if (![resultSet next]) { return (type)0; }                           \
type ret = [resultSet sel:0];                                        \
[resultSet close];                                                   \
[resultSet setParentDB:nil];                                         \
return ret;


- (OFString*)stringForQuery:(OFString*)query, ... {
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(OFString *, stringForColumnIndex);
}

- (int)intForQuery:(OFString*)query, ... {
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(int, intForColumnIndex);
}

- (long)longForQuery:(OFString*)query, ... {
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(long, longForColumnIndex);
}

- (BOOL)boolForQuery:(OFString*)query, ... {
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(BOOL, boolForColumnIndex);
}

- (double)doubleForQuery:(OFString*)query, ... {
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(double, doubleForColumnIndex);
}

- (OFDataArray*)dataForQuery:(OFString*)query, ... {
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(OFDataArray *, dataForColumnIndex);
}

- (OFDate*)dateForQuery:(OFString*)query, ... {
    RETURN_RESULT_FOR_QUERY_WITH_SELECTOR(OFDate *, dateForColumnIndex);
}


//check if table exist in database (patch from OZLB)
- (BOOL)tableExists:(OFString*)tableName {
    
    BOOL returnBool;
    //lower case table name
    tableName = [tableName lowercaseString];
    //search in sqlite_master table if table exists
    FMResultSet *rs = [self executeQuery:@"select [sql] from sqlite_master where [type] = 'table' and lower(name) = ?", tableName];
    //if at least one next exists, table exists
    returnBool = [rs next];
    //close and free object
    [rs close];
    
    return returnBool;
}

//get table with list of tables: result colums: type[STRING], name[STRING],tbl_name[STRING],rootpage[INTEGER],sql[STRING]
//check if table exist in database  (patch from OZLB)
- (FMResultSet*)getSchema {
    
    //result colums: type[STRING], name[STRING],tbl_name[STRING],rootpage[INTEGER],sql[STRING]
    FMResultSet *rs = [self executeQuery:@"SELECT type, name, tbl_name, rootpage, sql FROM (SELECT * FROM sqlite_master UNION ALL SELECT * FROM sqlite_temp_master) WHERE type != 'meta' AND name NOT LIKE 'sqlite_%' ORDER BY tbl_name, type DESC, name"];
    
    return rs;
}

//get table schema: result colums: cid[INTEGER], name,type [STRING], notnull[INTEGER], dflt_value[],pk[INTEGER]
- (FMResultSet*)getTableSchema:(OFString*)tableName {
    
    //result colums: cid[INTEGER], name,type [STRING], notnull[INTEGER], dflt_value[],pk[INTEGER]
    FMResultSet *rs = [self executeQuery:[OFString stringWithFormat: @"PRAGMA table_info(%@)", tableName]];
    
    return rs;
}


//check if column exist in table
- (BOOL)columnExists:(OFString*)tableName columnName:(OFString*)columnName {
    
    BOOL returnBool = NO;
    //lower case table name
    tableName = [tableName lowercaseString];
    //lower case column name
    columnName = [columnName lowercaseString];
    //get table schema
    FMResultSet *rs = [self getTableSchema: tableName];
    //check if column is present in table schema
    while ([rs next]) {
        if ([[[rs stringForColumn:@"name"] lowercaseString] isEqual: columnName]) {
            returnBool = YES;
            break;
        }
    }
    //close and free object
    [rs close];
    
    return returnBool;
}

- (BOOL)validateSQL:(OFString*)sql {
    sqlite3_stmt *pStmt = NULL;
    BOOL validationSucceeded = YES;
    BOOL keepTrying = YES;
    int numberOfRetries = 0;
    
    [self setInUse:YES];
    while (keepTrying == YES) {
        keepTrying = NO;
        int rc = sqlite3_prepare_v2(_db, [sql UTF8String], -1, &pStmt, 0);
        if (rc == SQLITE_BUSY || rc == SQLITE_LOCKED) {
            keepTrying = YES;
            [OFThread sleepForTimeInterval:0.00002];
            
            if (_busyRetryTimeout && (numberOfRetries++ > _busyRetryTimeout)) {
                of_log(@"%s:%d Database busy (%@)", sel_getName(_cmd), __LINE__, [self databasePath]);
                of_log(@"Database busy");
            }          
        } 
        else if (rc != SQLITE_OK) {
            validationSucceeded = NO;
            
        }
    }
    
    [self setInUse:NO];
    sqlite3_finalize(pStmt);
    
    return validationSucceeded;
}

@end
