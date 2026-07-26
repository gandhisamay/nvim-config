local ls = require("luasnip")

local s = ls.s
local i = ls.i
local t = ls.t

local d = ls.dynamic_node
local c = ls.choice_node
local f = ls.function_node
local sn = ls.snippet_node

local fmt = require("luasnip.extras.fmt").fmt

local snippets, autosnippets = {}, {}

local cppBoilerplate = s('bits', fmt([[
#include<bits/stdc++.h>
using namespace std;

#define sfor(i, l, r) for (int i = l; i < r; ++i)
#define bfor(i, r, l) for (int i = r; i >= l; --i)
#define endl "\n";
#define all(a) a.begin(), a.end()
#define int long long
using ll = long long;
using vi = vector<int>;
using ld = long double;
using pii = pair<int, int>;
using vvi = vector<vector<int>>;

const int INF = 1e18;
const int NINF = -1e18;

struct custom_hash
{{
  static uint64_t splitmix64(uint64_t x)
  {{
    x += 0x9e3779b97f4a7c15;
    x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9;
    x = (x ^ (x >> 27)) * 0x94d049bb133111eb;
    return x ^ (x >> 31);
  }}

  size_t operator()(uint64_t x) const
  {{
    static const uint64_t FIXED_RANDOM = chrono::steady_clock::now().time_since_epoch().count();
    return splitmix64(x + FIXED_RANDOM);
  }}
}};

template <typename T1, typename T2> // Key should be integer type
using safe_map = unordered_map<T1, T2, custom_hash>;
 
// Operator overloads
template <typename T1, typename T2> // cin >> pair<T1, T2>
istream &operator>>(istream &istream, pair<T1, T2> &p)
{{
  return (istream >> p.first >> p.second);
}}
 
template <typename T> // cin >> vector<T>
istream &operator>>(istream &istream, vector<T> &v)
{{
  for (auto &it : v)
    cin >> it;
  return istream;
}}
 
template <typename T1, typename T2> // cout << pair<T1, T2>
ostream &operator<<(ostream &ostream, const pair<T1, T2> &p)
{{
  return (ostream << p.first << " " << p.second);
}}

template <typename T> // cout << vector<T>
ostream &operator<<(ostream &ostream, const vector<T> &c)
{{
  for (auto &it : c)
    cout << it << " ";
  return ostream;
}}
 
// Utility functions
 
template <typename T>
int32_t size_i(T &container) {{ return static_cast<int32_t>(container.size()); }}

void solve(){{
 {}
}}

signed main(){{
    ios_base::sync_with_stdio(false);
    cin.tie(NULL);
    cout.tie(NULL);
    int t;
    cin>>t;

    while(t--){{
      solve();
    }}

    return 0;
}}

]], {
  i(1, "")
}))

local spf = s('spf', fmt([[
class SPF {{
public:
  vector<bool> isPrime;
  vector<int> hpf;
  vector<int> lpf;
  int N;
  SPF(int N){{
    this->N = N;
    isPrime.resize(N + 1, true);
    hpf.resize(N + 1);
    lpf.resize(N + 1, 0);

    isPrime[0] = false;
    isPrime[1] = false;

    for (int i = 2; i <= N; i++) {{
      if (isPrime[i]) {{
        lpf[i] = hpf[i] = i;
        for (int j = 2 * i; j <= N; j += i) {{
          isPrime[j] = false;
          hpf[j] = i;
          if (lpf[j] == 0)
            lpf[j] = i;
        }}
      }}
    }}
  }};
}};

]], {}))

local binexp = s('binexp', fmt([[ 
ll binexp(int a, int b) {{
  ll res = 1;
  ll pow = a;
  while (b) {{
    if (b & 1) {{
      res *= pow;
    }}
    pow *= pow;
    b >>= 1;
  }}

  return res;
}}

]], {}))

local dsu = s('dsu', fmt([[ 
int findSet(int i, vector<int> &parent) {{
  if (parent[i] == -1)
    return i;
  return parent[i] = findSet(parent[i], parent);
}}

void unionSet(int i, int k, vector<int> &parent, vector<int> &rank) {{
  int s1 = findSet(i, parent);
  int s2 = findSet(k, parent);

  if (s1 != s2) {{
    if (rank[s1] <= rank[s2])
      swap(s1, s2);
    rank[s1] += rank[s2];
    parent[s2] = s1;
  }}
}}

]], {}))

local bfs = s('bfs', fmt([[ 
void bfs(int src, vi &vis, vi adj[]) {{
  vis[src] = 1;
  queue<int> q;
  q.push(src);

  while (!q.empty()) {{
    int temp = q.front();
    q.pop();

    for (auto nbr : adj[temp]) {{
      if (!vis[nbr]) {{
        q.push(nbr);
        vis[nbr] = 1;
      }}
    }}
  }}
}}

]], {}))

local bs = s('bs', fmt([[ 
int binarySearch(int tar, vi nums) {{
  int lo = -1;
  int hi = nums.size();

  while (lo + 1 < hi) {{
    int mid = (hi - lo) / 2 + lo;
    if (nums[mid] == tar)
      return mid;
    else if (nums[mid] > tar)
      hi = mid;
    else
      lo = mid;
  }}

  return -1;
}}

]], {}))

local ncr = s('ncr', fmt([[
int power(int x, int n) {{
  if (n == 0)
    return 1;

  int ans = power(x, n / 2);
  ans *= ans;
  ans %= MOD;

  if (n % 2 != 0) {{
    ans *= x;
    ans %= MOD;
  }}

  return ans;
}}

int fact(int n) {{
  int ans = 1;

  for (int i = 1; i <= n; i++) {{
    ans *= i;
    ans %= MOD;
  }}

  return ans;
}}

int nCr(int n, int r) {{
  int ans = fact(n);
  int denominator = (fact(n - r) * fact(r)) % MOD;

  return (ans * power(denominator, MOD - 2)) % MOD;
}}

]], {}))

table.insert(snippets, cppBoilerplate)
table.insert(snippets, spf)
table.insert(snippets, binexp)
table.insert(snippets, dsu)
table.insert(snippets, bfs)
table.insert(snippets, bs)
table.insert(snippets, ncr)

return snippets, autosnippets
