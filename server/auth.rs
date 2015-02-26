use std::error;
use std::hash::{SipHasher, Hash, Hasher};
use std::rand;
use std::result;

use rusqlite::{SqliteConnection, SqliteError};
use rusqlite::types::ToSql;
use rusqlite::ffi::SQLITE_CONSTRAINT;

use util::StrError;


pub struct Auth {
    conn: SqliteConnection,
}

impl Auth {
    pub fn new(db_path: Path) -> Result<Auth> {
        let path_str = db_path.as_str().unwrap();
        let conn = try!(SqliteConnection::open(path_str));
        try!(conn.execute("CREATE TABLE IF NOT EXISTS auth (
                           name      TEXT NOT NULL UNIQUE,
                           secret    TEXT NOT NULL
                           )", &[]));
        Ok(Auth {
            conn: conn,
        })
    }

    pub fn register(&mut self, name: &str, secret: &Secret) -> Result<bool> {
        let hash = hash_secret(secret);
        let result = self.conn.execute("INSERT INTO auth (name, secret)
                                        VALUES ($1, $2)",
                                       &[&name as &ToSql,
                                         &&*hash as &ToSql]);
        match result {
            Ok(_) => Ok(true),
            // Constraint violation means the username is already registered.
            Err(ref e) if e.code == SQLITE_CONSTRAINT => Ok(false),
            Err(e) => Err(Error::Sqlite(e)),
        }
    }

    pub fn login(&mut self, name: &str, secret: &Secret) -> Result<bool> {
        let mut stmt = try!(self.conn.prepare("SELECT secret FROM auth WHERE name = $1"));

        for row in try!(stmt.query(&[&name as &ToSql])) {
            let row = try!(row);
            let hash: String = row.get(0);
            return match check_secret(secret, &*hash) {
                SecretMatch::Yes => Ok(true),
                SecretMatch::No => Ok(false),
                SecretMatch::YesNeedsRehash => {
                    let new_hash = hash_secret(secret);
                    try!(self.conn.execute("UPDATE auth SET secret = $2 WHERE name = $1",
                                           &[&name as &ToSql,
                                             &&*new_hash as &ToSql]));
                    Ok(true)
                },
            };
        }
        Ok(false)
    }
}



pub type Secret = [u32; 4];

pub fn hash_secret(s: &Secret) -> String {
    // TODO: use a better hash

    let salt0 = rand::random();
    let salt1 = rand::random();

    let mut sip = SipHasher::new_with_keys(salt0, salt1);
    for x in s.iter() {
        x.hash(&mut sip);
    }
    let hash = sip.finish();

    return format!("0;{};{};{}", salt0, salt1, hash);
}

enum SecretMatch {
    Yes,
    No,
    YesNeedsRehash,
}

pub fn check_secret(s: &Secret, hash: &str) -> SecretMatch {
    // TODO: use a better hash

    let idx = hash.find(';').unwrap();
    let version: u32 = hash.slice_to(idx).parse().unwrap();

    if version == 0 {
        let mut iter = hash.slice_from(idx + 1).split(';');
        let salt0 = iter.next().unwrap().parse().unwrap();
        let salt1 = iter.next().unwrap().parse().unwrap();
        let expect_hash = iter.next().unwrap().parse().unwrap();

        let mut sip = SipHasher::new_with_keys(salt0, salt1);
        for x in s.iter() {
            x.hash(&mut sip);
        }
        let hash = sip.finish();

        if hash == expect_hash {
            SecretMatch::Yes
        } else {
            SecretMatch::No
        }
    } else {
        SecretMatch::No
    }
}


#[derive(Show)]
pub enum Error {
    Str(StrError),
    Sqlite(SqliteError),
}

impl error::Error for Error {
    fn description(&self) -> &str {
        match *self {
            Error::Str(ref e) => e.description(),
            Error::Sqlite(ref e) => &*e.message,
        }
    }

    fn cause(&self) -> Option<&error::Error> {
        match *self {
            Error::Str(ref e) => Some(e as &error::Error),
            // SqliteError doesn't implement Error.
            Error::Sqlite(_) => None,
        }
    }
}

impl error::FromError<StrError> for Error {
    fn from_error(e: StrError) -> Error {
        Error::Str(e)
    }
}

impl error::FromError<SqliteError> for Error {
    fn from_error(e: SqliteError) -> Error {
        Error::Sqlite(e)
    }
}

pub type Result<T> = result::Result<T, Error>;

