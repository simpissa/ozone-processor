#include <bits/stdc++.h>

using namespace std;

string htob(string& s) {
    string out;
    for (auto i : s) {
        uint8_t n;
        if (i <= '9' and i >= '0')
            n = i - '0';
        else
            n = 10 + i - 'a';
        for (int8_t j = 3; j >= 0; --j)
            out.push_back((n & (1 << j)) ? '1' : '0');
    }
    return out;
}

int main() {
    fstream fin("input.txt");
    fstream fout("output.txt", ios::out);

    string valid;
    string fu_select = "000";
    string fu_op;
    string set_flags;
    string dest_valid;         // Set to false if writing to XZR
    string dest_tag;
    string src1_valid = "1";  // valid: is this register used in execution
    string src1_value;
    string src1_tag;
    string src1_ready;  // ready: is the value ready now; if 0, its currently executing and needs to be snooped with rob tag
    string src2_valid = "1";
    string src2_value;
    string src2_tag;
    string src2_ready;
    string imm = "0000000000000000000000000000000000000000000000000000000000000110";
    string imm_valid = "0";
    string cond = "0000";
    string bus_valid;
    string tag;
    string value;  // GPR result or resolved next PC for branches
    string flags = "0000";
    string flags_valid = "0";
    string exception = "0";  // fu exceptions can happen in mem and fpu; other exceptions are detected at commit-time in the rob
    string exception_code = "0000";

    string str = "";
    int cnt;
    fin >> cnt;
    while (cnt--) {
        fin >> valid;
        fin >> fu_op;
        fin >> set_flags;
        fin >> dest_valid;  // Set to false if writing to XZR
        fin >> dest_tag;
        fin >> src1_value;
        fin >> src1_tag;
        fin >> src1_ready;  // ready: is the value ready now; if 0, its currently executing and needs to be snooped with rob tag
        fin >> src2_value;
        fin >> src2_tag;
        fin >> src2_ready;
        fin >> bus_valid;
        fin >> tag;
        fin >> value;

        str += valid;
        str += fu_select;
        str += fu_op;
        str += set_flags;
        str += dest_valid;  // Set to false if writing to XZR
        str += dest_tag;
        str += src1_valid;  // valid: is this register used in execution
        str += htob(src1_value);
        str += src1_tag;
        str += src1_ready;  // ready: is the value ready now; if 0, its currently executing and needs to be snooped with rob tag
        str += src2_valid;
        str += htob(src2_value);
        str += src2_tag;
        str += src2_ready;
        str += imm;
        str += imm_valid;
        str += cond;
        str += bus_valid;
        str += tag;
        str += htob(value);  // GPR result or resolved next PC for branches
        str += flags;
        str += flags_valid;
        str += exception;  // fu exceptions can happen in mem and fpu; other exceptions are detected at commit-time in the rob
        str += exception_code;
        str += "\n";
    }
    fout << str;
    return 0;
}