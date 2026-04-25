#include <bits/stdc++.h>

using namespace std;

string htob(const string& s) {
  string out;
  out.reserve(s.size() * 4);
  for (char i : s) {
    uint8_t n;
    if (i >= '0' && i <= '9') {
      n = static_cast<uint8_t>(i - '0');
    } else if (i >= 'a' && i <= 'f') {
      n = static_cast<uint8_t>(10 + i - 'a');
    } else {
      n = static_cast<uint8_t>(10 + i - 'A');
    }
    for (int8_t j = 3; j >= 0; --j) {
      out.push_back((n & (1 << j)) ? '1' : '0');
    }
  }
  return out;
}

int main() {
  fstream fin("input.txt");
  fstream fout("output.txt", ios::out);

  string valid;
  string op;
  string src1;
  string src2;
  string tag;
  string respReady;

  int cnt = 0;
  fin >> cnt;

  string trace;
  while (cnt--) {
    fin >> valid >> op >> src1 >> src2 >> tag >> respReady;
    trace += valid;
    trace += op;
    trace += htob(src1);
    trace += htob(src2);
    trace += tag;
    trace += respReady;
    trace += "\n";
  }

  fout << trace;
  return 0;
}