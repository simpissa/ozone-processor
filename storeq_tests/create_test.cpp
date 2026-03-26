#include <bits/stdc++.h>

using namespace std;

int main() {
    fstream fin("input.txt");
    fstream fout("output.txt", ios::out);
    unsigned long long vaddr;
    unsigned long long id;
    bool valid_adr;
    unsigned long long value;
    bool v_val;
    unsigned long long search_addr;
    unsigned long long load_age;
    bool resolve;
    unsigned long long age;
    string str = "";

    while (fin >> vaddr) {
        fin >> id;
        fin >> valid_adr;
        fin >> value;
        fin >> v_val;
        fin >> search_addr;
        fin >> load_age;
        fin >> resolve;
        fin >> age;
        // cout << id << " " << valid_adr << " " << value << " " << v_val << " " << search_addr << " " << load_age << " " << resolve << " " << age;
        // for(int i=0;i<5;i++){
        //     str+=to_string(age&1);
        //     age>>=1;
        // }
        // str+=to_string(resolve&1);
        // for(int i=0;i<5;i++){
        //     str+=to_string(load_age&1);
        //     load_age>>=1;
        // }
        // for(int i=0;i<48;i++){
        //     str+=to_string(search_addr&1);
        //     search_addr>>=1;
        // }
        // str+=to_string(v_val&1);
        // for(int i=0;i<64;i++){
        //     str+=to_string(value&1);
        //     value>>=1;
        // }
        // str+=to_string(valid_adr&1);
        // for(int i=0;i<3;i++){
        //     str+='0';
        // }
        // for(int i=0;i<4;i++){
        //     str+=to_string(id&1);
        //     id>>=1;
        // }
        // for(int i=0;i<48;i++){
        //     str+=to_string(vaddr&1);
        //     vaddr>>=1;
        // }
        // str+="\n";

        string tmp = "";
        for (int i = 0; i < 48; i++) {
            tmp += to_string(vaddr & 1);
            vaddr >>= 1;
        }
        for (int i = 0; i < 4; i++) {
            tmp += to_string(id & 1);
            id >>= 1;
        }
        for (int i = 0; i < 3; i++) {
            tmp += '0';
        }
        tmp += to_string(valid_adr & 1);
        for (int i = 0; i < 64; i++) {
            tmp += to_string(value & 1);
            value >>= 1;
        }
        tmp += to_string(v_val & 1);
        for (int i = 0; i < 48; i++) {
            tmp += to_string(search_addr & 1);
            search_addr >>= 1;
        }
        for (int i = 0; i < 5; i++) {
            tmp += to_string(load_age & 1);
            load_age >>= 1;
        }
        tmp += to_string(resolve & 1);
        for (int i = 0; i < 5; i++) {
            tmp += to_string(age & 1);
            age >>= 1;
        }
        reverse(tmp.begin(), tmp.end());
        str += tmp;
        str += "\n";
    }
    fout << str;
    return 0;
}