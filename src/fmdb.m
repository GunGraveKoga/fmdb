#import <ObjFW/ObjFW.h>
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"

#define FMDBQuickCheck(SomeBool) { if (!(SomeBool)) { of_log(@"Failure on line %d", __LINE__); return 123; } }

int main (int argc, const char * argv[]) {
    OFAutoreleasePool * pool = [[OFAutoreleasePool alloc] init];
    
    // delete the old db.
    OFFileManager *fileManager = [OFFileManager defaultManager];
    if ([[OFFileManager defaultManager] fileExistsAtPath:[@"C:/Temp/tmp.db" stringByStandardizingPath]])
        [fileManager removeItemAtPath:[@"C:/Temp/tmp.db" stringByStandardizingPath]];
    
    FMDatabase *db = [FMDatabase databaseWithPath:[@"C:/Temp/tmp.db" stringByStandardizingPath]];
    
    of_log(@"Is SQLite compiled with it's thread safe options turned on? %@!", [FMDatabase isThreadSafe] ? @"Yes" : @"No");
    
    {
		// -------------------------------------------------------------------------------
		// Un-opened database check.		
		FMDBQuickCheck([db executeQuery:@"select * from table"] == nil);
		of_log(@"%d: %@", [db lastErrorCode], [db lastErrorMessage]);
	}
    
    
    if (![db open]) {
        of_log(@"Could not open db.");
        [pool drain];
        return 0;
    }
    
    // kind of experimentalish.
    [db setShouldCacheStatements:YES];
    
    // create a bad statement, just to test the error code.
    [db executeUpdate:@"blah blah blah"];
    
    FMDBQuickCheck([db hadError]);
    
    if ([db hadError]) {
        of_log(@"Err %d: %@", [db lastErrorCode], [db lastErrorMessage]);
    }
    
    
    FMDBQuickCheck(![db update:@"blah blah blah" bind:nil]);
    of_log(@"err: %d %@", [db lastErrorCode], [db lastErrorMessage]);
    
    // but of course, I don't bother checking the error codes below.
    // Bad programmer, no cookie.
    
    [db executeUpdate:@"create table test (a text, b text, c integer, d double, e double)"];
    
    
    [db beginTransaction];
    int i = 0;
    while (i++ < 20) {
        [db executeUpdate:@"insert into test (a, b, c, d, e) values (?, ?, ?, ?, ?)" ,
            @"hi'", // look!  I put in a ', and I'm not escaping it!
            [OFString stringWithFormat:@"number %d", i],
            [OFNumber numberWithInt:i],
            [OFDate date],
            [OFNumber numberWithFloat:2.2f]];
    }
    [db commit];
    
    
    
    // do it again, just because
    [db beginTransaction];
    i = 0;
    while (i++ < 20) {
        [db executeUpdate:@"insert into test (a, b, c, d, e) values (?, ?, ?, ?, ?)" ,
         @"hi again", // look!  I put in a ', and I'm not escaping it!
         [OFString stringWithFormat:@"number %d", i],
         [OFNumber numberWithInt:i],
         [OFDate date],
         [OFNumber numberWithFloat:2.2f]];
    }
    [db commit];
    
    
    
    
    
    FMResultSet *rs = [db executeQuery:@"select rowid,* from test where a = ?", @"hi'"];
    while ([rs next]) {
        // just print out what we've got in a number of formats.
        of_log(@"%d %@ %@ %@ %@ %f %f",
              [rs intForColumn:@"c"],
              [rs stringForColumn:@"b"],
              [rs stringForColumn:@"a"],
              [rs stringForColumn:@"rowid"],
              [rs dateForColumn:@"d"],
              [rs doubleForColumn:@"d"],
              [rs doubleForColumn:@"e"]);
        
        
        if (!([[rs columnNameForIndex:0] isEqual:@"rowid"] &&
              [[rs columnNameForIndex:1] isEqual:@"a"])
              ) {
            of_log(@"WHOA THERE BUDDY, columnNameForIndex ISN'T WORKING!");
            return 7;
        }
    }
    // close the result set.
    // it'll also close when it's dealloc'd, but we're closing the database before
    // the autorelease pool closes, so sqlite will complain about it.
    [rs close];  
    
    // ----------------------------------------------------------------------------------------
    // blob support.
    [db executeUpdate:@"create table blobTable (a text, b blob)"];
    
    // let's read in an image from safari's app bundle.
    OFDataArray *safariCompass = [OFDataArray dataArrayWithContentsOfFile:[@"C:/wamp/www/favicon.ico" stringByStandardizingPath]];
    if (safariCompass) {
        [db executeUpdate:@"insert into blobTable (a, b) values (?,?)", @"safari's compass", safariCompass];
        
        rs = [db executeQuery:@"select b from blobTable where a = ?", @"safari's compass"];
        if ([rs next]) {
            safariCompass = [rs dataForColumn:@"b"];
            [safariCompass writeToFile:[@"C:/Temp/compass.ico" stringByStandardizingPath]];
            
        }
        else {
            of_log(@"Could not select image.");
        }
        
        [rs close];
        
    }
    else {
        of_log(@"Can't find compass image..");
    }
    
    
    // test out the convenience methods in +Additions
    [db executeUpdate:@"create table t1 (a integer)"];
    [db executeUpdate:@"insert into t1 values (?)", [OFNumber numberWithInt:5]];
    
    of_log(@"Count of changes (should be 1): %d", [db changes]);
    FMDBQuickCheck([db changes] == 1);
    
    int a = [db intForQuery:@"select a from t1 where a = ?", [OFNumber numberWithInt:5]];
    if (a != 5) {
        of_log(@"intForQuery didn't work (a != 5)");
    }
    
    // test the busy rety timeout schtuff.
    
    [db setBusyRetryTimeout:50000];
    
    FMDatabase *newDb = [FMDatabase databaseWithPath:[@"C:/Temp/tmp.db" stringByStandardizingPath]];
    [newDb open];
    
    rs = [newDb executeQuery:@"select rowid,* from test where a = ?", @"hi'"];
    [rs next]; // just grab one... which will keep the db locked.
    
    of_log(@"Testing the busy timeout");
    
    BOOL success = [db executeUpdate:@"insert into t1 values (5)"];
    
    if (success) {
        of_log(@"Whoa- the database didn't stay locked!");
        return 7;
    }
    else {
        of_log(@"Hurray, our timeout worked");
    }
    
    [rs close];
    [newDb close];
    
    success = [db executeUpdate:@"insert into t1 values (5)"];
    if (!success) {
        of_log(@"Whoa- the database shouldn't be locked!");
        return 8;
    }
    else {
        of_log(@"Hurray, we can insert again!");
    }
    
    
    
    // test some nullness.
    [db executeUpdate:@"create table t2 (a integer, b integer)"];
    
    if (![db executeUpdate:@"insert into t2 values (?, ?)", nil, [OFNumber numberWithInt:5]]) {
        of_log(@"UH OH, can't insert a nil value for some reason...");
    }
    
    
    
    
    rs = [db executeQuery:@"select * from t2"];
    while ([rs next]) {
        OFString *a = [rs stringForColumnIndex:0];
        OFString *b = [rs stringForColumnIndex:1];
        
        if (a != nil) {
            of_log(@"%s:%d", __FUNCTION__, __LINE__);
            of_log(@"OH OH, PROBLEMO!");
            return 10;
        }
        else {
            of_log(@"YAY, NULL VALUES");
        }
        
        if (![b isEqual:@"5"]) {
            of_log(@"%s:%d", __FUNCTION__, __LINE__);
            of_log(@"OH OH, PROBLEMO!");
            return 10;
        }
    }
    
    
    
    
    
    
    
    
    
    
    // test some inner loop funkness.
    [db executeUpdate:@"create table t3 (a somevalue)"];
    
    
    // do it again, just because
    [db beginTransaction];
    i = 0;
    while (i++ < 20) {
        [db executeUpdate:@"insert into t3 (a) values (?)" , [OFNumber numberWithInt:i]];
    }
    [db commit];
    
    
    
    
    rs = [db executeQuery:@"select * from t3"];
    while ([rs next]) {
        int foo = [rs intForColumnIndex:0];
        
        int newVal = foo + 100;
        
        [db executeUpdate:@"update t3 set a = ? where a = ?" , [OFNumber numberWithInt:newVal], [OFNumber numberWithInt:foo]];
        
        
        FMResultSet *rs2 = [db executeQuery:@"select a from t3 where a = ?", [OFNumber numberWithInt:newVal]];
        [rs2 next];
        
        if ([rs2 intForColumnIndex:0] != newVal) {
            of_log(@"Oh crap, our update didn't work out!");
            return 9;
        }
        
        [rs2 close];
    }
    
    
    // NSNull tests
    [db executeUpdate:@"create table nulltest (a text, b text)"];
    
    [db executeUpdate:@"insert into nulltest (a, b) values (?, ?)" , [OFNull null], @"a"];
    [db executeUpdate:@"insert into nulltest (a, b) values (?, ?)" , nil, @"b"];
    
    rs = [db executeQuery:@"select * from nulltest"];
    
    while ([rs next]) {
        
        OFString *a = [rs stringForColumnIndex:0];
        OFString *b = [rs stringForColumnIndex:1];
        
        if (!b) {
            of_log(@"Oh crap, the nil / null inserts didn't work!");
            return 10;
        }
        
        if (a) {
            of_log(@"Oh crap, the nil / null inserts didn't work (son of error message)!");
            return 11;
        }
        else {
            of_log(@"HURRAH FOR NSNULL (and nil)!");
        }
    }
    
    
    
    
    
    
    // null dates
    
    OFDate *date = [OFDate date];
    [db executeUpdate:@"create table datetest (a double, b double, c double)"];
    [db executeUpdate:@"insert into datetest (a, b, c) values (?, ?, 0)" , [OFNull null], date];
    
    rs = [db executeQuery:@"select * from datetest"];
    
    while ([rs next]) {
        
        OFDate *a = [rs dateForColumnIndex:0];
        OFDate *b = [rs dateForColumnIndex:1];
        OFDate *c = [rs dateForColumnIndex:2];
        
        if (a) {
            of_log(@"Oh crap, the null date insert didn't work!");
            return 12;
        }
        
        if (!c) {
            of_log(@"Oh crap, the 0 date insert didn't work!");
            return 12;
        }
        
        of_time_interval_t dti = fabs([b timeIntervalSinceDate:date]);
        
        if (floor(dti) > 0.0) {
            of_log(@"Date matches didn't really happen... time difference of %f", dti);
            return 13;
        }
        
        
        dti = fabs([c timeIntervalSinceDate:[OFDate dateWithTimeIntervalSince1970:0]]);
        
        if (floor(dti) > 0.0) {
            of_log(@"Date matches didn't really happen... time difference of %f", dti);
            return 13;
        }
    }
    
    OFDate *foo = [db dateForQuery:@"select b from datetest where c = 0"];
    
    of_time_interval_t dti = fabs([foo timeIntervalSinceDate:date]);
    if (floor(dti) > 0.0) {
        of_log(@"Date matches didn't really happen... time difference of %f", dti);
        return 14;
    }
    
    [db executeUpdate:@"create table nulltest2 (s text, d data, i integer, f double, b integer)"];
    
    [db executeUpdate:@"insert into nulltest2 (s, d, i, f, b) values (?, ?, ?, ?, ?)" , @"Hi", safariCompass, [OFNumber numberWithInt:12], [OFNumber numberWithFloat:4.4f], [OFNumber numberWithBool:YES]];
    [db executeUpdate:@"insert into nulltest2 (s, d, i, f, b) values (?, ?, ?, ?, ?)" , nil, nil, nil, nil, [OFNull null]];
    
    rs = [db executeQuery:@"select * from nulltest2"];
    
    while ([rs next]) {
        
        int i = [rs intForColumnIndex:2];
        
        if (i == 12) {
            // it's the first row we inserted.
            FMDBQuickCheck(![rs columnIndexIsNull:0]);
            FMDBQuickCheck(![rs columnIndexIsNull:1]);
            FMDBQuickCheck(![rs columnIndexIsNull:2]);
            FMDBQuickCheck(![rs columnIndexIsNull:3]);
            FMDBQuickCheck(![rs columnIndexIsNull:4]);
            FMDBQuickCheck( [rs columnIndexIsNull:5]);
            
            FMDBQuickCheck([[rs dataForColumn:@"d"] count] == [safariCompass count]);
            FMDBQuickCheck(![rs dataForColumn:@"notthere"]);
            FMDBQuickCheck(![rs stringForColumnIndex:-2]);
            FMDBQuickCheck([rs boolForColumnIndex:4]);
            FMDBQuickCheck([rs boolForColumn:@"b"]);
            
            FMDBQuickCheck(fabs(4.4 - [rs doubleForColumn:@"f"]) < 0.0000001);
            
            FMDBQuickCheck(12 == [rs intForColumn:@"i"]);
            FMDBQuickCheck(12 == [rs intForColumnIndex:2]);
            
            FMDBQuickCheck(0 == [rs intForColumnIndex:12]); // there is no 12
            FMDBQuickCheck(0 == [rs intForColumn:@"notthere"]);
            
            FMDBQuickCheck(12 == [rs longForColumn:@"i"]);
            FMDBQuickCheck(12 == [rs longLongIntForColumn:@"i"]);
        }
        else {
            // let's test various null things.
            
            FMDBQuickCheck([rs columnIndexIsNull:0]);
            FMDBQuickCheck([rs columnIndexIsNull:1]);
            FMDBQuickCheck([rs columnIndexIsNull:2]);
            FMDBQuickCheck([rs columnIndexIsNull:3]);
            FMDBQuickCheck([rs columnIndexIsNull:4]);
            FMDBQuickCheck([rs columnIndexIsNull:5]);
            
            
            FMDBQuickCheck(![rs dataForColumn:@"d"]);
            
        }
    }
    
    
    
    {
        [db executeUpdate:@"create table testOneHundredTwelvePointTwo (a text, b integer)"];
        [db executeUpdate:@"insert into testOneHundredTwelvePointTwo values (?, ?)" withArgumentsInArray:[OFArray arrayWithObjects:@"one", [OFNumber numberWithInt:2], nil]];
        [db executeUpdate:@"insert into testOneHundredTwelvePointTwo values (?, ?)" withArgumentsInArray:[OFArray arrayWithObjects:@"one", [OFNumber numberWithInt:3], nil]];
        
        
        rs = [db executeQuery:@"select * from testOneHundredTwelvePointTwo where b > ?" withArgumentsInArray:[OFArray arrayWithObject:[OFNumber numberWithInt:1]]];
        
        FMDBQuickCheck([rs next]);
        
        FMDBQuickCheck([rs hasAnotherRow]);
        FMDBQuickCheck(![db hadError]);
        
        FMDBQuickCheck([[rs stringForColumnIndex:0] isEqual:@"one"]);
        FMDBQuickCheck([rs intForColumnIndex:1] == 2);
        
        FMDBQuickCheck([rs next]);
        
        FMDBQuickCheck([rs intForColumnIndex:1] == 3);
        
        FMDBQuickCheck(![rs next]);
        FMDBQuickCheck(![rs hasAnotherRow]);
        
    }
    
    {
        
        FMDBQuickCheck([db executeUpdate:@"create table t4 (a text, b text)"]);
        FMDBQuickCheck(([db executeUpdate:@"insert into t4 (a, b) values (?, ?)", @"one", @"two"]));
        
        rs = [db executeQuery:@"select t4.a as 't4.a', t4.b from t4;"];
        
        FMDBQuickCheck((rs != nil));
        
        [rs next];
        
        FMDBQuickCheck([[rs stringForColumn:@"t4.a"] isEqual:@"one"]);
        FMDBQuickCheck([[rs stringForColumn:@"b"] isEqual:@"two"]);
        
        FMDBQuickCheck(strcmp((const char*)[rs UTF8StringForColumnName:@"b"], "two") == 0);
        
        [rs close];
        
        // let's try these again, with the withArgumentsInArray: variation
        FMDBQuickCheck([db executeUpdate:@"drop table t4;" withArgumentsInArray:[OFArray array]]);
        FMDBQuickCheck([db executeUpdate:@"create table t4 (a text, b text)" withArgumentsInArray:[OFArray array]]);
        FMDBQuickCheck(([db executeUpdate:@"insert into t4 (a, b) values (?, ?)" withArgumentsInArray:[OFArray arrayWithObjects:@"one", @"two", nil]]));
        
        rs = [db executeQuery:@"select t4.a as 't4.a', t4.b from t4;" withArgumentsInArray:[OFArray array]];
        
        FMDBQuickCheck((rs != nil));
        
        [rs next];
        
        FMDBQuickCheck([[rs stringForColumn:@"t4.a"] isEqual:@"one"]);
        FMDBQuickCheck([[rs stringForColumn:@"b"] isEqual:@"two"]);
        
        FMDBQuickCheck(strcmp((const char*)[rs UTF8StringForColumnName:@"b"], "two") == 0);
        
        [rs close];
    }
    
    
    
    
    {
        FMDBQuickCheck([db tableExists:@"t4"]);
        FMDBQuickCheck(![db tableExists:@"thisdoesntexist"]);
        
        rs = [db getSchema];
        while ([rs next]) {
            FMDBQuickCheck([[rs stringForColumn:@"type"] isEqual:@"table"]);
        }
    }
    
    
    {
        FMDBQuickCheck([db executeUpdate:@"create table t5 (a text, b int, c blob, d text, e text)"]);
        FMDBQuickCheck(([db executeUpdateWithFormat:@"insert into t5 values (%s, %d, %@, %c, %lld)", "text", 42, @"BLOB", 'd', 12345678901234]));
        
        rs = [db executeQueryWithFormat:@"select * from t5 where a = %s", "text"];
        FMDBQuickCheck((rs != nil));
        
        [rs next];
        
        FMDBQuickCheck([[rs stringForColumn:@"a"] isEqual:@"text"]);
        FMDBQuickCheck(([rs intForColumn:@"b"] == 42));
        FMDBQuickCheck([[rs stringForColumn:@"c"] isEqual:@"BLOB"]);
        FMDBQuickCheck([[rs stringForColumn:@"d"] isEqual:@"d"]);
        FMDBQuickCheck(([rs longLongIntForColumn:@"e"] == 12345678901234));
    }
    
    
    
    // just for fun.
    rs = [db executeQuery:@"PRAGMA database_list"];
    while ([rs next]) {
        OFString *file = [rs stringForColumn:@"file"];
        of_log(@"database_list: %@", file);
    }
    
    
    // print out some stats if we are using cached statements.
    if ([db shouldCacheStatements]) {
        
        for (FMStatement *statement in [[db cachedStatements] allObjects]) {
            of_log(@"%@", statement);
        }
        
    }
    of_log(@"That was version %@ of sqlite", [FMDatabase sqliteLibVersion]);
    
    
    [db close];
    
    [pool release];
    return 0;
}
