#import <ObjFW/OFObject.h>
#import "sqlite3.h"
#import "FMResultSet.h"

@class OFString;
@class OFMutableSet;
@class OFMutableDictionary;
@class OFArray;

@interface FMDatabase : OFObject 
{
	sqlite3*    _db;
	OFString*   _databasePath;
    BOOL        _logsErrors;
    BOOL        _crashOnErrors;
    BOOL        _inUse;
    BOOL        _inTransaction;
    BOOL        _traceExecution;
    BOOL        _checkedOut;
    int         _busyRetryTimeout;
    BOOL        _shouldCacheStatements;
    OFMutableDictionary *_cachedStatements;
	OFMutableSet *_openResultSets;
}


@property (assign) BOOL inTransaction;
@property (assign) BOOL traceExecution;
@property (assign) BOOL checkedOut;
@property (assign) int busyRetryTimeout;
@property (assign) BOOL crashOnErrors;
@property (assign) BOOL logsErrors;
@property (retain) OFMutableDictionary *cachedStatements;


+ (id)databaseWithPath:(OFString*)inPath;
- (id)initWithPath:(OFString*)inPath;

- (BOOL)open;
#if SQLITE_VERSION_NUMBER >= 3005000
- (BOOL)openWithFlags:(int)flags;
#endif
- (BOOL)close;
- (BOOL)goodConnection;
- (void)clearCachedStatements;
- (void)closeOpenResultSets;

// encryption methods.  You need to have purchased the sqlite encryption extensions for these to work.
- (BOOL)setKey:(OFString*)key;
- (BOOL)rekey:(OFString*)key;


- (OFString *)databasePath;

- (OFString*)lastErrorMessage;

- (int)lastErrorCode;
- (BOOL)hadError;
- (sqlite_int64)lastInsertRowId;

- (sqlite3*)sqliteHandle;

- (BOOL)update:(OFString*)sql bind:(id)bindArgs, ...;
- (BOOL)executeUpdate:(OFString*)sql, ...;
- (BOOL)executeUpdateWithFormat:(OFString *)format, ...;
- (BOOL)executeUpdate:(OFString*)sql withArgumentsInArray:(OFArray *)arguments;
- (BOOL)executeUpdate:(OFString*)sql withArgumentsInArray:(OFArray*)arrayArgs orVAList:(va_list)args; // you shouldn't ever need to call this.  use the previous two instead.

- (FMResultSet *)executeQuery:(OFString*)sql, ...;
- (FMResultSet *)executeQueryWithFormat:(OFString*)format, ...;
- (FMResultSet *)executeQuery:(OFString *)sql withArgumentsInArray:(OFArray *)arguments;
- (FMResultSet *)executeQuery:(OFString *)sql withArgumentsInArray:(OFArray*)arrayArgs orVAList:(va_list)args; // you shouldn't ever need to call this.  use the previous two instead.

- (BOOL)rollback;
- (BOOL)commit;
- (BOOL)beginTransaction;
- (BOOL)beginDeferredTransaction;

- (BOOL)inUse;
- (void)setInUse:(BOOL)value;


- (BOOL)shouldCacheStatements;
- (void)setShouldCacheStatements:(BOOL)value;

+ (BOOL)isThreadSafe;
+ (OFString*)sqliteLibVersion;

- (int)changes;

@end

@interface FMStatement : OFObject {
    sqlite3_stmt *_statement;
    OFString *_query;
    long _useCount;
}

@property (assign) long useCount;
@property (retain) OFString *query;
@property (assign) sqlite3_stmt *statement;

- (void)close;
- (void)reset;

@end

