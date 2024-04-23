// Copyright (c) 2023, WSO2 LLC. (http://www.wso2.org) All Rights Reserved.

// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at

//    http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/uuid;
import ballerina/http;
import ballerina/jwt;
import ballerina/sql;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;

enum Status {
    reading = "reading",
    read = "read",
    to_read = "to_read"
}


type Result record {|
    string registrationId;
    string firstName;
    string lastName;
|};

type BookItem record {|
    string title;
    string author;
    string status;
|};

type Book record {|
    *BookItem;
    string id;
|};

map<map<Book>> books = {};
const string DEFAULT_USER = "default";

service /readinglist on new http:Listener(9090) {

    resource function get books(http:Headers headers) returns Book[]{
        Book[] sampleBooks = [
        {id:"1",title: "Book 1", author: "Author 1", status: "reading"},
        {id:"2",title: "Book 2", author: "Author 2", status: "read"},
        {id:"3",title: "Book 3", author: "Author 3", status: "to_read"}
    ];

        return sampleBooks;
    }

    resource function get books2(http:Headers headers) returns json|error{
        mysql:Client mysqlClient = check new (host = "choreo-shared-mysql.mysql.database.azure.com",
                                            user = "readonly-sampleuser@choreo-shared-mysql.mysql.database.azure.com",
                                            password = "non_confidential_password",
                                            database = "customers_db", port = 3306);

        stream<Result, sql:Error?> resultStream = mysqlClient->query(`SELECT registrationId, firstName, lastName FROM Customers 
                                                WHERE country="usa"`);
        map<json> resultOutput = {};

        check from Result {registrationId, firstName, lastName} in resultStream
            do {
                resultOutput[registrationId] = {firstName, lastName};
            };

        return resultOutput;
    }


    resource function post books(http:Headers headers,
                                 @http:Payload BookItem newBook) returns http:Created|http:BadRequest|error {

        string bookId = uuid:createType1AsString();
        map<Book>|http:BadRequest usersBooks = check getUsersBooks(headers);
        if (usersBooks is map<Book>) {
            usersBooks[bookId] = {...newBook, id: bookId};
            return <http:Created>{};
        }
        return <http:BadRequest>usersBooks;
    }

    resource function delete books(http:Headers headers,
                                   string id) returns http:Ok|http:BadRequest|error? {
        map<Book>|http:BadRequest usersBooks = check getUsersBooks(headers);
        if (usersBooks is map<Book>) {
            _ = usersBooks.remove(id);
            return <http:Ok>{};
        }
        return <http:BadRequest>usersBooks;
    }
}

// This function is used to get the books of the user who is logged in.
// User information is extracted from the JWT token.
function getUsersBooks(http:Headers headers) returns map<Book>|http:BadRequest|error {
        string|error jwtAssertion = headers.getHeader("x-jwt-assertion");
        if (jwtAssertion is error) {
            http:BadRequest badRequest = {
                body: {
                    "error": "Bad Request",
                    "error_description": "Error while getting the JWT token"
                }
            };
            return badRequest;
        }

        [jwt:Header, jwt:Payload] [_, payload] = check jwt:decode(jwtAssertion);
        string username = payload.sub is string ? <string>payload.sub : DEFAULT_USER;
        if (books[username] is ()) {
            books[username] = {};
        }
        return <map<Book>>books[username];
    }
