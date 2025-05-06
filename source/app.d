import std.stdio : writeln, writefln;
import std.string : endsWith, split;
import std.file : read, write;
import std.conv : to;
import std.zip;

import dxml.parser;
import apiqqut.collection.list : ArrayList;

string markdownText = "";

TextData[] datas = new TextData[0];
TextData holder = TextData();

enum TextStyle {
    Blod,
    Incl,
    Delete,
    FirstTitle,
    SecondTitle,
    SubTitle
}

struct TextData {
    string text = "";
    TextStyle[] styles = new TextStyle[0];
    int tableStyle = 0;
}

string byte2string(ubyte[] b) pure nothrow {
    string s;
    foreach (bt; b) {
        s ~= to!char(bt);
    }
    return s;
}

string setStyleData(TextStyle style, string target, bool ignoreTitle = false) {
    final switch (style) {
    case TextStyle.FirstTitle:
        if (ignoreTitle)
            break;
        target = "# " ~ target;
        break;

    case TextStyle.SecondTitle:
        if (ignoreTitle)
            break;
        target = "## " ~ target;
        break;

    case TextStyle.SubTitle:
        if (ignoreTitle)
            break;
        target = "### " ~ target;
        break;

    case TextStyle.Blod:
        target ~= "**";
        break;

    case TextStyle.Incl:
        target ~= "*";
        break;

    case TextStyle.Delete:
        target ~= "~~";
        break;
    }
    return target;
}

bool hasStyle(TextStyle[] arr, TextStyle style) {
    foreach (st; arr) {
        if (st == style) {
            return true;
        }
    }
    return false;
}

TextStyle[] removeStyle(TextStyle[] arr, TextStyle style) {
    TextStyle[] styleArray = new TextStyle[0];
    foreach (st; arr) {
        if (st != style) {
            styleArray ~= st;
        }
    }
    return styleArray;
}

TextStyle[] tirmStyle(TextStyle[] arr) {
    TextStyle[] styleArray = new TextStyle[0];

    foreach (st; arr) {
        if (st == TextStyle.FirstTitle || st == TextStyle.SecondTitle || st == TextStyle.SubTitle) {
            continue;
        }
        styleArray ~= st;
    }
    return styleArray;
}

string push() {
    string textIn = "";
    TextStyle[] lasterStyle = new TextStyle[0];

    foreach (txt; datas) {
        TextStyle[] styleData = new TextStyle[0] ~ txt.styles;
        if (lasterStyle.length > 0) {
            foreach (laster; lasterStyle) {
                if (hasStyle(styleData, laster)) {
                    styleData = removeStyle(styleData, laster);
                    continue;
                }
                styleData = laster ~ styleData;
                lasterStyle = removeStyle(lasterStyle, laster);
            }
        } else {
            lasterStyle ~= txt.styles;
        }

        lasterStyle = tirmStyle(lasterStyle);

        foreach (style; styleData) {
            textIn = setStyleData(style, textIn);
        }

        textIn ~= txt.text;
    }

    foreach (style; lasterStyle) {
        textIn = setStyleData(style, textIn, true);
    }

    datas = new TextData[0];
    return textIn ~ "  \n";
}

void findTitleType(EntityRange!(Config.init, string) range) {
    auto aRange = range.front.attributes;
    while (!aRange.empty) {
        if (aRange.front.name != "w:val") {
            aRange.popFront;
            continue;
        }

        string val = aRange.front.value;

        holder.styles ~= val == "1"
            ? TextStyle.FirstTitle : val == "2"
            ? TextStyle.SecondTitle : TextStyle.SubTitle;

        return;
    }
}

void findJCType(EntityRange!(Config.init, string) range) {
    auto aRange = range.front.attributes;
    while (!aRange.empty) {
        if (aRange.front.name != "w:val") {
            aRange.popFront;
            continue;
        }

        string val = aRange.front.value;

        holder.tableStyle = val == "center"
            ? 1 : val == "right"
            ? 2 : 0;

        return;
    }
}

void putStyle(EntityRange!(Config.init, string) range) {
    switch (range.front.name) {
    case "w:b":
        holder.styles ~= TextStyle.Blod;
        return;
    case "w:i":
        holder.styles ~= TextStyle.Incl;
        return;
    case "w:strike":
        holder.styles ~= TextStyle.Delete;
        return;
    default:
        return;
    }
}

void createTable(EntityRange!(Config.init, string)* rangePot) {
    TextData[][][] table = new TextData[][][0];
    int tableCol = -1;

    bool start = false;

    while (!(*rangePot).empty) {
        switch ((*rangePot).front.type) {
        case EntityType.elementStart:
            switch ((*rangePot).front.name) {
            case "w:tr":
                table ~= new TextData[][0];
                ++tableCol;
                break;

            case "w:r":
                start = true;
                break;

            case "w:t":
                (*rangePot).popFront;
                holder.text = (*rangePot).front.text;
                datas ~= holder;
                holder = TextData();
                start = false;
                break;

            default:
                break;
            }
            break;
        case EntityType.elementEnd:
            switch ((*rangePot).front.name) {
            case "w:tc":
                table[tableCol] ~= datas;
                datas = new TextData[0];
                break;

            case "w:tbl":
                string tb = "";
                bool title = true;
                string[] style = new string[0];
                foreach (keyRow; table) {
                    foreach (keys; keyRow) {
                        if (keys.length < 1) {
                            continue;
                        }
                        if (title) {
                            TextData key = keys[0];
                            style ~= key.tableStyle == 1 ? ":---:" : key.tableStyle == 2 ? "---:"
                                : ":---";
                        }

                        datas = keys;
                        string dat = push()[0 .. $ - 3];
                        tb ~= "|" ~ dat;
                    }
                    tb ~= "|\n";
                    if (title) {
                        title = false;
                        foreach (string k; style) {
                            tb ~= "|" ~ k;
                        }
                        tb ~= "|\n";
                    }
                }

                markdownText ~= "\n" ~ tb ~ "\n";

                return;

            default:
                break;
            }
            break;

        case EntityType.elementEmpty:
            switch ((*rangePot).front.name) {
            case "w:tr":
                table[tableCol] ~= datas;
                tableCol++;
                break;

            case "w:jc":
                findJCType((*rangePot));
                break;

            default:
                if (start) {
                    putStyle((*rangePot));
                }
                break;
            }

            break;

        default:
            break;
        }

        (*rangePot).popFront;
    }
}

void parse(string dataIn) {

    auto range = parseXML(dataIn);
    bool start = false;

    while (!range.empty) {
        switch (range.front.type) {
        case EntityType.elementEnd:
            if (range.front.name == "w:p") {
                markdownText ~= push();
            }
            break;

        case EntityType.elementEmpty:
            if (range.front.name == "w:pStyle") {
                findTitleType(range);
            } else if (start) {
                putStyle(range);
            }
            break;

        case EntityType.elementStart:
            if (range.front.name == "w:tbl") {
                createTable(&range);
            } else if (range.front.name == "w:r") {
                start = true;
            } else if (range.front.name == "w:t") {
                range.popFront;
                holder.text = range.front.type != EntityType.elementEnd ? range.front.text : " ";
                datas ~= holder;
                holder = TextData();
                start = false;
            }
            break;
        default:
            break;
        }

        range.popFront;
    }
}

int main(string[] args) {
    if (args.length < 2) {
        writeln("Please input a doc or docx file!");
        return 1;
    }

    string fileInput = args[1];
    if (!fileInput.endsWith(".doc") && !fileInput.endsWith(".docx")) {
        writeln("Please input a doc or docx file!");
        return 1;
    }

    auto zip = new ZipArchive(read(fileInput));

    string xmlData = null;
    foreach (name, am; zip.directory) {
        if (name != "word/document.xml") {
            continue;
        }
        xmlData = byte2string(zip.expand(am));
    }

    if (xmlData is null) {
        writeln("The doc(x) file is breakon!");
        return 1;
    }

    parse(xmlData);

    string filename = "./" ~ args[1].split(".")[0] ~ ".md";

    write(filename, markdownText);

    return 0;
}
