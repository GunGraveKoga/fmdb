#import <ObjFW/ObjFW.h>
#import "FMDatabase.h"
#include <unistd.h>
#include <assert.h>

@implementation FMDatabase

@synthesize inTransaction = _inTransaction;
@synthesize cachedStatements = _cachedStatements;
@synthesize logsErrors = _logsErrors;
@synthesize crashOnErrors = _crashOnErrors;
@synthesize busyRetryTimeout = _busyRetryTimeout;
@synthesize checkedOut = _checkedOut;
@synthesize traceExecution = _traceExecution;

+ (instancetype)databaseWithPath:(OFString*)aPath {
    return [[[self alloc] initWithPath:aPath] autorelease];
}

- (instancetype)initWithPath:(OFString*)aPath {
    self = [super init];
    
    
    _databasePath        = [aPath copy];
    _openResultSets      = [[OFMutableSet alloc] init];
    _db                  = 0x00;
    _logsErrors          = 0x00;
    _crashOnErrors       = 0x00;
    _busyRetryTimeout    = 0x00;
    
    
    return self;
}

- (void)dealloc {
    [self close];
    
    [_openResultSets release];
    [_cachedStatements release];
    [_databasePath release];
    
    [super dealloc];
}

+ (OFString*)sqliteLibVersion {
    return [OFString stringWithFormat:@"%s", sqlite3_libversion()];
}

- (OFString *)databasePath {
    return _databasePath;
}

- (sqlite3*)sqliteHandle {
    return _db;
}

- (BOOL)open {
    if (_db) {
        return YES;
    }
    
    int err = sqlite3_open((_databasePath ? [[_databasePath stringByStandardizingPath] UTF8String] : ":memory:"), &_db );
    if(err != SQLITE_OK) {
        of_log(@"error opening!: %d", err);
        return NO;
    }
    
    return YES;
}

#if SQLITE_VERSION_NUMBER >= 3005000
- (BOOL)openWithFlags:(int)flags {
    int err = sqlite3_open_v2((_databasePath ? [[_databasePath stringByStandardizingPath] UTF8String] : ":memory:"), &_db, flags, NULL /* Name of VFS module to use */);
    if(err != SQLITE_OK) {
        of_log(@"error opening!: %d", err);
        return NO;
    }
    return YES;
}
#endif


- (BOOL)close {
    
    [self clearCachedStatements];
    [self closeOpenResultSets];
    
    if (!_db) {
        return YES;
    }
    
    int  rc;
    BOOL retry;
    int numberOfRetries = 0;
    BOOL triedFinalizingOpenStatements = NO;
    
    do {
        retry   = NO;
        rc      = sqlite3_close(_db);
        if (SQLITE_BUSY == rc || SQLITE_LOCKED == rc) {
            retry = YES;
            [OFThread sleepForTimeInterval:0.00002];
            if (_busyRetryTimeout && (numberOfRetries++ > _busyRetryTimeout)) {
                of_log(@"%s:%d", sel_getName(_cmd), __LINE__);
                of_log(@"Database busy, unable to close");
                return NO;
            }
            
            if (!triedFinalizingOpenStatements) {
                triedFinalizingOpenStatements = YES;
                sqlite3_stmt *pStmt;
                while ((pStmt = sqlite3_next_stmt(_db, 0x00)) !=0) {
                    of_log(@"Closing leaked statement");
                    sqlite3_finalize(pStmt);
                }
            }
        }
        else if (SQLITE_OK != rc) {
            of_log(@"error closing!: %d", rc);
        }
    }
    while (retry);
    
    _db = NULL;
    return YES;
}

- (void)clearCachedStatements {
    
    for (FMStatement *cachedStmt in [_cachedStatements allObjects]) {
        [cachedStmt close];
    }

    [_cachedStatements removeAllObjects];
    
}

- (void)closeOpenResultSets {
    //Copy the set so we don't get mutation errors
    OFSet *resultSets = [[_openResultSets copy] autorelease];

    for (FMResultSet *rs in resultSets) {
        if ([rs respondsToSelector:@selector(close)]) {
            [rs close];
        }
    }
    
}

- (void)resultSetDidClose:(FMResultSet *)resultSet {
    [_openResultSets removeObject:resultSet];
}

- (FMStatement*)cachedStatementForQuery:(OFString*)query {
    return [_cachedStatements objectForKey:query];
}

- (void)setCachedStatement:(FMStatement*)statement forQuery:(OFString*)query {
    //of_log(@"setting query: %@", query);
    query = [query copy]; // in case we got handed in a mutable string...
    [statement setQuery:query];
    [_cachedStatements setObject:statement forKey:query];
    [query release];
}


- (BOOL)rekey:(OFString*)key {
#ifdef SQLITE_HAS_CODEC
    if (!key) {
        return NO;
    }
    
    int rc = sqlite3_rekey(db, [key UTF8String], [key UTF8StringLength]);
    
    if (rc != SQLITE_OK) {
        of_log(@"error on rekey: %d", rc);
        of_log(@"%@", [self lastErrorMessage]);
    }
    
    return (rc == SQLITE_OK);
#else
    return NO;
#endif
}

- (BOOL)setKey:(OFString*)key {
#ifdef SQLITE_HAS_CODEC
    if (!key) {
        return NO;
    }
    
    int rc = sqlite3_key(db, [key UTF8String], [key UTF8StringLength]);
    
    return (rc == SQLITE_OK);
#else
    return NO;
#endif
}

- (BOOL)goodConnection {
    
    if (!_db) {
        return NO;
    }
    
    FMResultSet *rs = [self executeQuery:@"select name from sqlite_master where type='table'"];
    
    if (rs) {
        [rs close];
        return YES;
    }
    
    return NO;
}

- (void)warnInUse {
    of_log(@"The FMDatabase %@ is currently in use.", self);
    
#ifndef NS_BLOCK_ASSERTIONS
    if (_crashOnErrors) {
        of_log(@"The FMDatabase %@ is currently in use.", self);
        @throw [OFException exception];
    }
#endif
}

- (BOOL)databaseExists {
    
    if (!_db) {
            
        of_log(@"The FMDatabase %@ is not open.", self);
        
    #ifndef NS_BLOCK_ASSERTIONS
        if (_crashOnErrors) {
            of_log(@"The FMDatabase %@ is not open.", self);
            @throw [OFException exception];
        }
    #endif
        
        return NO;
    }
    
    return YES;
}

- (OFString*)lastErrorMessage {
    return [OFString stringWithUTF8String:sqlite3_errmsg(_db)];
}

- (BOOL)hadError {
    int lastErrCode = [self lastErrorCode];
    
    return (lastErrCode > SQLITE_OK && lastErrCode < SQLITE_ROW);
}

- (int)lastErrorCode {
    return sqlite3_errcode(_db);
}

- (sqlite_int64)lastInsertRowId {
    
    if (_inUse) {
        [self warnInUse];
        return NO;
    }
    [self setInUse:YES];
    
    sqlite_int64 ret = sqlite3_last_insert_rowid(_db);
    
    [self setInUse:NO];
    
    return ret;
}

- (int)changes {
    if (_inUse) {
        [self warnInUse];
        return 0;
    }
    
    [self setInUse:YES];
    int ret = sqlite3_changes(_db);
    [self setInUse:NO];
    
    return ret;
}

- (void)bindObject:(id)obj toColumn:(int)idx inStatement:(sqlite3_stmt*)pStmt {
    
    if ((!obj) || ((OFNull *)obj == [OFNull null])) {
        sqlite3_bind_null(pStmt, idx);
    }
    
    // FIXME - someday check the return codes on these binds.
    else if ([obj isKindOfClass:[OFDataArray class]]) {
        OFDataArray* dataObj = obj;
        sqlite3_bind_blob(pStmt, idx, [dataObj items], (int)([dataObj count] * [dataObj itemSize]), SQLITE_STATIC);
    }
    else if ([obj isKindOfClass:[OFDate class]]) {
        sqlite3_bind_double(pStmt, idx, [obj timeIntervalSince1970]);
    }
    else if ([obj isKindOfClass:[OFNumber class]]) {
        OFNumber* numberObj = obj;
        if (numberObj.type == OF_NUMBER_TYPE_BOOL) {
            sqlite3_bind_int(pStmt, idx, ([numberObj boolValue] ? 1 : 0));
        }
        else if (numberObj.type == OF_NUMBER_TYPE_INT) {
            sqlite3_bind_int64(pStmt, idx, [numberObj longValue]);
        }
        else if (numberObj.type == OF_NUMBER_TYPE_LONG) {
            sqlite3_bind_int64(pStmt, idx, [numberObj longValue]);
        }
        else if (numberObj.type == OF_NUMBER_TYPE_LONGLONG) {
            sqlite3_bind_int64(pStmt, idx, [numberObj longLongValue]);
        }
        else if (numberObj.type == OF_NUMBER_TYPE_FLOAT) {
            sqlite3_bind_double(pStmt, idx, [numberObj floatValue]);
        }
        else if (numberObj.type == OF_NUMBER_TYPE_DOUBLE) {
            sqlite3_bind_double(pStmt, idx, [numberObj doubleValue]);
        }
        else {
            sqlite3_bind_text(pStmt, idx, [[numberObj description] UTF8String], -1, SQLITE_STATIC);
        }
    }
    else {
        sqlite3_bind_text(pStmt, idx, [[obj description] UTF8String], -1, SQLITE_STATIC);
    }
}

- (void)_extractSQL:(OFString *)sql argumentsList:(va_list)args intoString:(OFMutableString *)cleanedSQL arguments:(OFMutableArray *)arguments {
    
    size_t length = [sql length];
    of_unichar_t last = '\0';
    for (size_t i = 0; i < length; ++i) {
        id arg = nil;
        of_unichar_t current = [sql characterAtIndex:i];
        of_unichar_t add = current;
        if (last == '%') {
            switch (current) {
                case '@':
                    arg = va_arg(args, id); break;
                case 'c':
                    arg = [OFString stringWithFormat:@"%c", va_arg(args, int)]; break;
                case 's':
                    arg = [OFString stringWithUTF8String:va_arg(args, char*)]; break;
                case 'd':
                case 'D':
                case 'i':
                    arg = [OFNumber numberWithInt:va_arg(args, int)]; break;
                case 'u':
                case 'U':
                    arg = [OFNumber numberWithUnsignedInt:va_arg(args, unsigned int)]; break;
                case 'h':
                    i++;
                    if (i < length && [sql characterAtIndex:i] == 'i') {
                        arg = [OFNumber numberWithInt:va_arg(args, int)];
                    }
                    else if (i < length && [sql characterAtIndex:i] == 'u') {
                        arg = [OFNumber numberWithInt:va_arg(args, int)];
                    }
                    else {
                        i--;
                    }
                    break;
                case 'q':
                    i++;
                    if (i < length && [sql characterAtIndex:i] == 'i') {
                        arg = [OFNumber numberWithLongLong:va_arg(args, long long)];
                    }
                    else if (i < length && [sql characterAtIndex:i] == 'u') {
                        arg = [OFNumber numberWithUnsignedLongLong:va_arg(args, unsigned long long)];
                    }
                    else {
                        i--;
                    }
                    break;
                case 'f':
                    arg = [OFNumber numberWithDouble:va_arg(args, double)]; break;
                case 'g':
                    arg = [OFNumber numberWithDouble:va_arg(args, double)]; break;
                case 'l':
                    i++;
                    if (i < length) {
                        of_unichar_t next = [sql characterAtIndex:i];
                        if (next == 'l') {
                            i++;
                            if (i < length && [sql characterAtIndex:i] == 'd') {
                                //%lld
                                arg = [OFNumber numberWithLongLong:va_arg(args, long long)];
                            }
                            else if (i < length && [sql characterAtIndex:i] == 'u') {
                                //%llu
                                arg = [OFNumber numberWithUnsignedLongLong:va_arg(args, unsigned long long)];
                            }
                            else {
                                i--;
                            }
                        }
                        else if (next == 'd') {
                            //%ld
                            arg = [OFNumber numberWithLong:va_arg(args, long)];
                        }
                        else if (next == 'u') {
                            //%lu
                            arg = [OFNumber numberWithUnsignedLong:va_arg(args, unsigned long)];
                        }
                        else {
                            i--;
                        }
                    }
                    else {
                        i--;
                    }
                    break;
                default:
                    // something else that we can't interpret. just pass it on through like normal
                    break;
            }
        }
        else if (current == '%') {
            // percent sign; skip this character
            add = '\0';
        }
        
        if (arg != nil) {
            [cleanedSQL appendString:@"?"];
            [arguments addObject:arg];
        }
        else if (add != '\0') {
            [cleanedSQL appendFormat:@"%C", add];
        }
        last = current;
    }
    
}

- (FMResultSet *)executeQuery:(OFString *)sql withArgumentsInArray:(OFArray*)arrayArgs orVAList:(va_list)args {
    
    if (![self databaseExists]) {
        return nil;
    }
    
    if (_inUse) {
        [self warnInUse];
        return nil;
    }
    
    [self setInUse:YES];
    
    FMResultSet *rs = nil;
    
    int rc                  = 0x00;
    sqlite3_stmt *pStmt     = 0x00;
    FMStatement *statement  = 0x00;
    
    if (_traceExecution && sql) {
        of_log(@"%@ executeQuery: %@", self, sql);
    }
    
    if (_shouldCacheStatements) {
        statement = [self cachedStatementForQuery:sql];
        pStmt = statement ? [statement statement] : 0x00;
    }
    
    int numberOfRetries = 0;
    BOOL retry          = NO;
    
    if (!pStmt) {
        do {
            retry   = NO;
            rc      = sqlite3_prepare_v2(_db, [sql UTF8String], -1, &pStmt, 0);
            
            if (SQLITE_BUSY == rc || SQLITE_LOCKED == rc) {
                retry = YES;
                [OFThread sleepForTimeInterval:0.00002];
                
                if (_busyRetryTimeout && (numberOfRetries++ > _busyRetryTimeout)) {
                    of_log(@"%s:%d Database busy (%@)", sel_getName(_cmd), __LINE__, [self databasePath]);
                    of_log(@"Database busy");
                    sqlite3_finalize(pStmt);
                    [self setInUse:NO];
                    return nil;
                }
            }
            else if (SQLITE_OK != rc) {
                
                
                if (_logsErrors) {
                    of_log(@"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                    of_log(@"DB Query: %@", sql);
#ifndef NS_BLOCK_ASSERTIONS
                    if (_crashOnErrors) {
                        of_log(@"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                        @throw [OFException exception];
                    }
#endif
                }
                
                sqlite3_finalize(pStmt);
                
                [self setInUse:NO];
                return nil;
            }
        }
        while (retry);
    }
    
    id obj;
    int idx = 0;
    int queryCount = sqlite3_bind_parameter_count(pStmt); // pointed out by Dominic Yu (thanks!)
    
    while (idx < queryCount) {
        
        if (arrayArgs) {
            obj = [arrayArgs objectAtIndex:idx];
        }
        else {
            obj = va_arg(args, id);
        }
        
        if (_traceExecution) {
            of_log(@"obj: %@", obj);
        }
        
        idx++;
        
        [self bindObject:obj toColumn:idx inStatement:pStmt];
    }
    
    if (idx != queryCount) {
        of_log(@"Error: the bind count is not correct for the # of variables (executeQuery)");
        sqlite3_finalize(pStmt);
        [self setInUse:NO];
        return nil;
    }
    
    [statement retain]; // to balance the release below
    
    if (!statement) {
        statement = [[FMStatement alloc] init];
        [statement setStatement:pStmt];
        
        if (_shouldCacheStatements) {
            [self setCachedStatement:statement forQuery:sql];
        }
    }
    
    // the statement gets closed in rs's dealloc or [rs close];
    rs = [FMResultSet resultSetWithStatement:statement usingParentDatabase:self];
    [rs setQuery:sql];
    
    [_openResultSets addObject:rs];
    
    statement.useCount = statement.useCount + 1;
    
    [statement release];    
    
    [self setInUse:NO];
    
    return rs;
}

- (FMResultSet *)executeQuery:(OFString*)sql, ... {
    va_list args;
    va_start(args, sql);
    
    id result = [self executeQuery:sql withArgumentsInArray:nil orVAList:args];
    
    va_end(args);
    return result;
}

- (FMResultSet *)executeQueryWithFormat:(OFString*)format, ... {
    va_list args;
    va_start(args, format);
    
    OFMutableString *sql = [OFMutableString string];
    OFMutableArray *arguments = [OFMutableArray array];
    [self _extractSQL:format argumentsList:args intoString:sql arguments:arguments];    
    
    va_end(args);
    
    return [self executeQuery:sql withArgumentsInArray:arguments];
}

- (FMResultSet *)executeQuery:(OFString *)sql withArgumentsInArray:(OFArray *)arguments {
    return [self executeQuery:sql withArgumentsInArray:arguments orVAList:NULL];
}

- (BOOL)executeUpdate:(OFString*)sql withArgumentsInArray:(OFArray*)arrayArgs orVAList:(va_list)args {
    
    if (![self databaseExists]) {
        return NO;
    }
    
    if (_inUse) {
        [self warnInUse];
        return NO;
    }
    
    [self setInUse:YES];
    
    int rc                   = 0x00;
    sqlite3_stmt *pStmt      = 0x00;
    FMStatement *cachedStmt  = 0x00;
    
    if (_traceExecution && sql) {
        of_log(@"%@ executeUpdate: %@", self, sql);
    }
    
    if (_shouldCacheStatements) {
        cachedStmt = [self cachedStatementForQuery:sql];
        pStmt = cachedStmt ? [cachedStmt statement] : 0x00;
    }
    
    int numberOfRetries = 0;
    BOOL retry          = NO;
    
    if (!pStmt) {
        
        do {
            retry   = NO;
            rc      = sqlite3_prepare_v2(_db, [sql UTF8String], -1, &pStmt, 0);
            if (SQLITE_BUSY == rc || SQLITE_LOCKED == rc) {
                retry = YES;
                [OFThread sleepForTimeInterval:0.00002];
                
                if (_busyRetryTimeout && (numberOfRetries++ > _busyRetryTimeout)) {
                    of_log(@"%s:%d Database busy (%@)", sel_getName(_cmd), __LINE__, [self databasePath]);
                    of_log(@"Database busy");
                    sqlite3_finalize(pStmt);
                    [self setInUse:NO];
                    return NO;
                }
            }
            else if (SQLITE_OK != rc) {
                
                
                if (_logsErrors) {
                    of_log(@"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                    of_log(@"DB Query: %@", sql);
#ifndef NS_BLOCK_ASSERTIONS
                    if (_crashOnErrors) {
                        of_log(@"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                        @throw [OFException exception];
                    }
#endif
                }
                
                sqlite3_finalize(pStmt);
                [self setInUse:NO];
                
                return NO;
            }
        }
        while (retry);
    }
    
    
    id obj;
    int idx = 0;
    int queryCount = sqlite3_bind_parameter_count(pStmt);
    
    while (idx < queryCount) {
        
        if (arrayArgs) {
            obj = [arrayArgs objectAtIndex:idx];
        }
        else {
            obj = va_arg(args, id);
        }
        
        
        if (_traceExecution) {
            of_log(@"obj: %@", obj);
        }
        
        idx++;
        
        [self bindObject:obj toColumn:idx inStatement:pStmt];
    }
    
    if (idx != queryCount) {
        of_log(@"Error: the bind count is not correct for the # of variables (%@) (executeUpdate)", sql);
        sqlite3_finalize(pStmt);
        [self setInUse:NO];
        return NO;
    }
    
    /* Call sqlite3_step() to run the virtual machine. Since the SQL being
     ** executed is not a SELECT statement, we assume no data will be returned.
     */
    numberOfRetries = 0;
    do {
        rc      = sqlite3_step(pStmt);
        retry   = NO;
        
        if (SQLITE_BUSY == rc || SQLITE_LOCKED == rc) {
            // this will happen if the db is locked, like if we are doing an update or insert.
            // in that case, retry the step... and maybe wait just 10 milliseconds.
            retry = YES;
            if (SQLITE_LOCKED == rc) {
                rc = sqlite3_reset(pStmt);
                if (rc != SQLITE_LOCKED) {
                    of_log(@"Unexpected result from sqlite3_reset (%d) eu", rc);
                }
            }
            [OFThread sleepForTimeInterval:0.00002];
            
            if (_busyRetryTimeout && (numberOfRetries++ > _busyRetryTimeout)) {
                of_log(@"%s:%d Database busy (%@)", sel_getName(_cmd), __LINE__, [self databasePath]);
                of_log(@"Database busy");
                retry = NO;
            }
        }
        else if (SQLITE_DONE == rc || SQLITE_ROW == rc) {
            // all is well, let's return.
        }
        else if (SQLITE_ERROR == rc) {
            of_log(@"Error calling sqlite3_step (%d: %s) SQLITE_ERROR", rc, sqlite3_errmsg(_db));
            of_log(@"DB Query: %@", sql);
        }
        else if (SQLITE_MISUSE == rc) {
            // uh oh.
            of_log(@"Error calling sqlite3_step (%d: %s) SQLITE_MISUSE", rc, sqlite3_errmsg(_db));
            of_log(@"DB Query: %@", sql);
        }
        else {
            // wtf?
            of_log(@"Unknown error calling sqlite3_step (%d: %s) eu", rc, sqlite3_errmsg(_db));
            of_log(@"DB Query: %@", sql);
        }
        
    } while (retry);
    
    assert( rc!=SQLITE_ROW );
    
    
    if (_shouldCacheStatements && !cachedStmt) {
        cachedStmt = [[FMStatement alloc] init];
        
        [cachedStmt setStatement:pStmt];
        
        [self setCachedStatement:cachedStmt forQuery:sql];
        
        [cachedStmt release];
    }
    
    if (cachedStmt) {
        cachedStmt.useCount = cachedStmt.useCount + 1;
        rc = sqlite3_reset(pStmt);
    }
    else {
        /* Finalize the virtual machine. This releases all memory and other
         ** resources allocated by the sqlite3_prepare() call above.
         */
        rc = sqlite3_finalize(pStmt);
    }
    
    [self setInUse:NO];
    
    return (rc == SQLITE_OK);
}


- (BOOL)executeUpdate:(OFString*)sql, ... {
    va_list args;
    va_start(args, sql);
    
    BOOL result = [self executeUpdate:sql withArgumentsInArray:nil orVAList:args];
    
    va_end(args);
    return result;
}



- (BOOL)executeUpdate:(OFString*)sql withArgumentsInArray:(OFArray *)arguments {
    return [self executeUpdate:sql withArgumentsInArray:arguments orVAList:NULL];
}

- (BOOL)executeUpdateWithFormat:(OFString*)format, ... {
    va_list args;
    va_start(args, format);
    
    OFMutableString *sql = [OFMutableString string];
    OFMutableArray *arguments = [OFMutableArray array];
    [self _extractSQL:format argumentsList:args intoString:sql arguments:arguments];    
    
    va_end(args);
    
    return [self executeUpdate:sql withArgumentsInArray:arguments];
}

- (BOOL)update:(OFString*)sql bind:(id)bindArgs, ... {
    va_list args;
    va_start(args, bindArgs);
    
    BOOL result = [self executeUpdate:sql withArgumentsInArray:nil orVAList:args];
    
    va_end(args);
    return result;
}

- (BOOL)rollback {
    BOOL b = [self executeUpdate:@"ROLLBACK TRANSACTION;"];
    if (b) {
        _inTransaction = NO;
    }
    return b;
}

- (BOOL)commit {
    BOOL b =  [self executeUpdate:@"COMMIT TRANSACTION;"];
    if (b) {
        _inTransaction = NO;
    }
    return b;
}

- (BOOL)beginDeferredTransaction {
    BOOL b =  [self executeUpdate:@"BEGIN DEFERRED TRANSACTION;"];
    if (b) {
        _inTransaction = YES;
    }
    return b;
}

- (BOOL)beginTransaction {
    BOOL b =  [self executeUpdate:@"BEGIN EXCLUSIVE TRANSACTION;"];
    if (b) {
        _inTransaction = YES;
    }
    return b;
}



- (BOOL)inUse {
    return _inUse || _inTransaction;
}

- (void)setInUse:(BOOL)b {
    _inUse = b;
}


- (BOOL)shouldCacheStatements {
    return _shouldCacheStatements;
}

- (void)setShouldCacheStatements:(BOOL)value {
    
    _shouldCacheStatements = value;
    
    if (_shouldCacheStatements && !_cachedStatements) {
        [self setCachedStatements:[OFMutableDictionary dictionary]];
    }
    
    if (!_shouldCacheStatements) {
        [self setCachedStatements:nil];
    }
}

+ (BOOL)isThreadSafe {
    // make sure to read the sqlite headers on this guy!
    return sqlite3_threadsafe();
}

@end



@implementation FMStatement

@synthesize statement = _statement;
@synthesize query = _query;
@synthesize useCount = _useCount;


- (void)dealloc {
    [self close];
    [_query release];
    [super dealloc];
}

- (void)close {
    if (_statement) {
        sqlite3_finalize(_statement);
        _statement = 0x00;
    }
}

- (void)reset {
    if (_statement) {
        sqlite3_reset(_statement);
    }
}

- (OFString*)description {
    return [OFString stringWithFormat:@"%@ %d hit(s) for query %@", [super description], _useCount, _query];
}


@end

