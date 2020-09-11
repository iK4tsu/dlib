/*
Copyright (c) 2018-2020 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

/**
 * JSON parser
 *
 * Copyright: Timur Gafarov 2018-2020.
 * License: $(LINK2 boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Timur Gafarov
 */
module dlib.serialization.json;

import std.stdio;
import std.conv;
import std.string;
import std.ascii;

import dlib.core.memory;
import dlib.core.compound;
import dlib.container.array;
import dlib.container.dict;
import dlib.text.utils;
import dlib.text.utf8;
import dlib.text.lexer;
import dlib.text.str;

class JSONLexer
{
    Lexer lexer;
    string text;
    string currentLexeme = "";
    String internalString;
    UTF8Encoder encoder;

    enum delimiters = [
        "{", "}", "[", "]", ",", ":", "\n", " ", "\"", "\'", "`",
        "\\a", "\\b", "\\f", "\\n", "\\r", "\\t", "\\v", "\\\"", "\\\'", "\\\\", "\\?",
        "\\u"
    ];

    this(string text)
    {
        this.text = text;
        internalString.reserve(text.length);
        lexer = New!Lexer(this.text, delimiters);
        nextLexeme();
    }

    ~this()
    {
        Delete(lexer);
        internalString.free();
    }

    void nextLexeme()
    {
        string lexeme;
        while (true)
        {
            lexeme = lexer.getLexeme();
            if (lexeme.length == 0)
            {
                internalString ~= lexeme;
                currentLexeme = cast(string)(internalString.data[$-lexeme.length..$]);
                return;
            }
            else if (lexeme != "\n" && !isWhitespace(lexeme))
            {
                if (lexeme == "\"" || lexeme == "\'" || lexeme == "`")
                {
                    string quote = lexeme;
                    size_t startPos = internalString.length;
                    internalString ~= lexeme;
                    size_t endPos = startPos;
                    while (lexeme.length)
                    {
                        lexeme = lexer.getLexeme();

                        if (lexeme == "\\a") internalString ~= "\a";
                        else if (lexeme == "\\b") internalString ~= "\b";
                        else if (lexeme == "\\f") internalString ~= "\f";
                        else if (lexeme == "\\n") internalString ~= "\n";
                        else if (lexeme == "\\r") internalString ~= "\r";
                        else if (lexeme == "\\t") internalString ~= "\t";
                        else if (lexeme == "\\v") internalString ~= "\v";
                        else if (lexeme == "\\\"") internalString ~= "\"";
                        else if (lexeme == "\\\'") internalString ~= "\'";
                        else if (lexeme == "\\\\") internalString ~= "\\";
                        else if (lexeme == "\\?") internalString ~= "\?";
                        else if (lexeme == "\\u")
                        {
                            lexeme = lexer.getLexeme();
                            char[4] buffer;
                            auto num = hexToUTF8(lexeme, buffer);
                            internalString ~= cast(string)(buffer[0..num]);
                        }
                        else internalString ~= lexeme;

                        endPos = internalString.length;
                        if (lexeme == quote)
                            break;
                    }
                    currentLexeme = cast(string)(internalString.data[startPos..endPos]);
                    return;
                }
                else
                {
                    internalString ~= lexeme;
                    currentLexeme = cast(string)(internalString.data[$-lexeme.length..$]);
                    return;
                }
            }
        }
    }

    bool isWhitespace(string lexeme)
    {
        return isWhite(lexeme[0]);
    }

    size_t hexToUTF8(string input, ref char[4] buffer)
    {
        uint codepoint = '\u0000';

        // TODO: invalid codepoint should be an error
        if (input.length >= 4)
        {
            string hex = input[0..4];
            codepoint = std.conv.parse!(uint, string)(hex, 16);
        }

        return encoder.encode(codepoint, buffer);
    }
}

/// JSON types enum
enum JSONType
{
    Null,
    Number,
    String,
    Array,
    Object
}

/// JSON array
alias JSONArray = Array!JSONValue;

/// JSON object
alias JSONObject = Dict!(JSONValue, string);

/// JSON value
class JSONValue
{
    JSONType type;
    double asNumber;
    string asString;
    JSONArray asArray;
    JSONObject asObject;

    this()
    {
        asNumber = 0.0;
        asString = "";
        asObject = null;
    }

    void addArrayElement(JSONValue element)
    {
        type = JSONType.Array;
        asArray.append(element);
    }

    void addField(string name, JSONValue element)
    {
        if (asObject is null)
            asObject = New!JSONObject();
        type = JSONType.Object;
        asObject[name] = element;
    }

    ~this()
    {
        if (asArray.length)
        {
            foreach(i, e; asArray.data)
                Delete(e);
            asArray.free();
        }

        if (asObject)
        {
            foreach(name, e; asObject)
                Delete(e);
            Delete(asObject);
        }
    }
}

/// JSON parsing result
alias JSONResult = Compound!(bool, string);

/// JSON parsing errors enum
enum JSONError
{
    EOI = JSONResult(false, "unexpected end of input")
}

/// JSON document
class JSONDocument
{
    public:
    bool isValid;
    JSONValue root;

    this(string input)
    {
        root = New!JSONValue();
        root.type = JSONType.Object;
        lexer = New!JSONLexer(input);
        JSONResult res = parseValue(root);
        isValid = res[0];
        if (!isValid)
            writeln(res[1]);
    }

    ~this()
    {
        Delete(root);
        Delete(lexer);
    }

    protected:

    JSONLexer lexer;
    string currentLexeme() @property
    {
        return lexer.currentLexeme;
    }

    void nextLexeme()
    {
        lexer.nextLexeme();
    }

    JSONResult parseValue(JSONValue value)
    {
        if (!currentLexeme.length)
            return JSONError.EOI;

        if (currentLexeme == "{")
        {
            nextLexeme();
            while (currentLexeme.length && currentLexeme != "}")
            {
                string identifier = currentLexeme;
                if (!identifier.length)
                    return JSONError.EOI;
                if (identifier[0] != '\"' || identifier[$-1] != '\"')
                    return JSONResult(false, format("illegal identifier \"%s\"", identifier));
                identifier = identifier[1..$-1];

                nextLexeme();
                if (currentLexeme != ":")
                    return JSONResult(false, format("\":\" expected, got \"%s\"", currentLexeme));

                nextLexeme();
                JSONValue newValue = New!JSONValue();
                JSONResult res = parseValue(newValue);
                if (!res[0])
                    return res;

                value.addField(identifier, newValue);

                nextLexeme();

                if (currentLexeme == ",")
                    nextLexeme();
                else if (currentLexeme != "}")
                    return JSONResult(false, format("\"}\" expected, got \"%s\"", currentLexeme));
            }
        }
        else if (currentLexeme == "[")
        {
            nextLexeme();
            while (currentLexeme.length && currentLexeme != "]")
            {
                JSONValue newValue = New!JSONValue();
                JSONResult res = parseValue(newValue);
                if (!res[0])
                    return res;

                value.addArrayElement(newValue);

                nextLexeme();

                if (currentLexeme == ",")
                    nextLexeme();
                else if (currentLexeme != "]")
                    return JSONResult(false, format("\"}\" expected, got \"%s\"", currentLexeme));
            }
        }
        else
        {
            string data = currentLexeme;
            if (data[0] == '\"')
            {
                if (data[$-1] != '\"')
                    return JSONResult(false, format("illegal string \"%s\"", data));
                data = data[1..$-1];
                value.type = JSONType.String;
                value.asString = data;
            }
            else
            {
                value.type = JSONType.Number;
                value.asNumber = data.to!double;
            }
        }

        return JSONResult(true, "");
    }
}
