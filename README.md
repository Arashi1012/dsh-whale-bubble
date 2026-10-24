# 灏忛哺楸兼皵娉?路 dsh-whale-bubble

妗岄潰涓婃偓娴竴鍙?**DeepSeek 瀹樻柟灏忛哺楸?*锛屼綔涓?DeepSeek Harness 鐨勬闈㈢姸鎬佹寕浠讹細

- 甯搁┗ **62脳62** 閫忔槑缃《绐楀彛锛屼笉鎶㈢劍鐐广€佷笉杩涗换鍔℃爮銆佺偣鍑荤┛閫忥紱
- **宸ヤ綔鏃舵父鍔?*锛氭暣鍙哺楸兼槸涓€鏉￠棴鍚堣矾寰勶紝灏惧反鍋氬集鏇插舰鍙樹笂涓嬫憜鍔紙闆舵帴缂濓級锛?- **鎮仠鏄剧ず杩涘害鍗?*锛氭爣棰?/ 绗?N 姝?路 鐢ㄦ椂 / 褰撳墠鍔ㄤ綔鎽樿 / 缁嗚繘搴︽潯锛岀Щ寮€鑷姩鏀惰捣锛?- **瀹屾垚鏃舵彁閱?*锛氶哺楸艰烦涓€涓?+ 宸︿笂瑙掑皬缁跨偣 + 鎻愮ず闊筹紱
- **鐐瑰嚮鍒囨崲 DSH 绐楀彛**锛氫笉鍦ㄥ墠鍙扳啋杩樺師缃墠锛屽凡鍦ㄥ墠鍙扳啋鏈€灏忓寲锛涘彲鎷栧姩銆佷綅缃蹇嗐€?
![骞虫椂锛氬彧鏈夐哺楸糫(docs/bubble.png)
![鎮仠锛氬伐浣滀腑](docs/hover-working.png)
![鎮仠锛氬畬鎴愭€乚(docs/hover-done.png)

娓稿姩鍔ㄧ敾锛堜粠杩愯涓殑鎮诞绐楁姄甯э級锛?
![娓稿姩鍔ㄧ敾](docs/swim.gif)

## 鐜瑕佹眰

| 椤?| 瑕佹眰 |
|---|---|
| 绯荤粺 | Windows 10 / 11 |
| 杩愯鏃?| Windows PowerShell 5.1锛堢郴缁熻嚜甯︼紝鏃犻渶瀹夎锛?|
| Harness | DeepSeek Harness Desktop锛坄desktop` profile锛夛紝鎻掍欢 API 鍩轰簬 `@deepseek-ai/cordis` 4.x |
| 渚濊禆 | 鏃犵涓夋柟 npm 渚濊禆銆佹棤鏋勫缓姝ラ |

## 瀹夎

```sh
git clone https://github.com/Arashi1012/dsh-whale-bubble.git
dsh plugin --profile desktop add "<鍏嬮殕涓嬫潵鐨勭洰褰曠粷瀵硅矾寰?"
```

涔熷彲浠ヨ Agent 鐢ㄦ彃浠剁鐞嗗櫒鐨?`install_bundle` 鎸囧悜璇ョ洰褰曞畨瑁呫€傚畨瑁呭悗鎻掍欢绔嬪嵆鐢熸晥骞惰嚜鍔ㄦ媺璧锋闈㈡皵娉★紱
閲嶅惎 DSH 浼氳嚜鍔ㄥ姞杞姐€?
鍗歌浇锛?
```sh
dsh plugin --profile desktop remove dsh-whale-bubble
```

## 閰嶇疆

`cordis.patch.yml` 涓殑 `config`锛?
```yaml
- insert:
    - id: whale-bubble
      name: 'dsh-whale-bubble'
      config:
        port: 43980    # 鏈満鐘舵€佹湇鍔＄鍙ｏ紝琚崰鐢ㄦ椂鑷姩椤哄欢
        sound: true    # 瀹屾垚浠诲姟鏃舵槸鍚︽挱鏀炬彁绀洪煶
```

## 宸ヤ綔鍘熺悊

- **Host 鎻掍欢**锛坄index.js`锛夌洃鍚?Harness 鐨?`session/event`锛坄turn/start`銆乣tool/call`銆乣assistant/message`銆乣turn/end`锛夛紝
  鍦?`127.0.0.1` 涓婃毚闇?`/state`锛屽苟鎷夎捣 / 鐪嬫姢妗岄潰姘旀场杩涚▼锛涘瓙鏅鸿兘浣撲細璇濅笉瑙﹀彂瀹屾垚鎻愰啋銆?- **姘旀场鏈綋**锛坄whale-bubble.ps1`锛夋槸 Windows PowerShell 5.1 + WPF 鐨勯€忔槑缃《绐楀彛锛?  杞 `/state` 娓叉煋鍔ㄧ敾涓庢偓鍋滃崱鐗囥€?- **灏惧反鍔ㄧ敾**锛氬惎鍔ㄦ椂鎶?`whale.svg` 鐨勫畼鏂?path 鎵佸钩鍖栵紝鍦ㄥ熬宸存牴閮ㄤ袱涓閮ㄧ偣澶勬媶鎴愯韩浣撴锛?38 鐐癸級涓庡熬槌嶆锛?5 鐐癸級锛?  姣忓抚閲嶅缓涓€鏉￠棴鍚堣矾寰勶紝灏鹃硩鍚勭偣鎸夊埌鏍归儴寮︾嚎鐨勮窛绂诲姞鏉冪粫璇ョ偣鏃嬭浆锛堟牴閮?0掳銆佸熬灏栨渶澶?卤14掳锛夛紝
  閰嶅悎 `GeometryGroup` 闈為浂濉厖淇濈暀鐧借倸/鐧界溂瀛旀礊 鈥斺€?鎵€浠ュ熬宸存憜鍔ㄦ椂杞粨濮嬬粓杩炵画锛岄潤姝㈡椂涓庡畼鏂?logo 瀹屽叏涓€鑷淬€?- **鎮仠**锛氬垎灞傜獥鍙ｅ彧鏈変笉閫忔槑鍍忕礌鍙懡涓紱鍗＄墖灞曞紑鍚庣敤 Win32 `GetCursorPos + PtInRect` 杞鍒ゆ柇鍏夋爣鏄惁浠嶅湪绐楀彛鍐咃紝
  閬垮厤绐楀彛鏀惧ぇ鐬棿 WPF 璇彂 `MouseLeave` 閫犳垚鐨勯棯鐑併€?
璋冭瘯绔偣锛堜粎鍥炵幆锛夛細`GET /state`銆乣/health`銆乣/log`銆乣/screenshot`锛堣嚜娓叉煋蹇収锛夈€乣/demo`锛堟紨绀哄畬鎴愭彁閱掞級銆乣POST /quit`銆?
杩愯鏃舵枃浠朵綅浜?`%LOCALAPPDATA%\dsh-whale-bubble\`锛歚plugin.log`銆乣bubble.log`銆乣position.json`銆乣preview.png`銆?
## 宸茬煡闄愬埗

- 浠?Windows锛圵PF + Win32锛夈€?- 鍙窡韪牴浼氳瘽锛屽瓙鏅鸿兘浣撲細璇濈粨鏉熶笉浼氳Е鍙戝畬鎴愭彁閱掋€?- 杩涘害鍗＄墖鍙湪鎮仠鏃跺嚭鐜帮紱绌洪棽鏃舵偓鍋滀笉浼氬脊鍑虹┖鍗＄墖銆?- 姘旀场鎸夊眰绐楀彛閫愬儚绱犲懡涓細椴搁奔涓庡崱鐗囩殑涓嶉€忔槑鍍忕礌鍙偣鍙嫋锛屽叾浣欏尯鍩熺偣鍑荤┛閫忋€?
## 璁稿彲璇佷笌鑷磋阿

- 浠ｇ爜锛歁IT锛岃 [LICENSE](LICENSE)銆?- 椴搁奔鏍囧織锛歚whale.svg` 鍙栬嚜 DeepSeek Harness Web 鍓嶇 `favicon.svg`锛圖eepSeek 鍝佺墝璧勪骇锛岀増鏉冨綊 DeepSeek 鎵€鏈夛級锛?  鏈粨搴撲粎灏嗚鏍囧織鐢ㄤ綔鎻掍欢鐨勫浘鏍囦笌鍔ㄧ敾绱犳潗锛岃瑙?[NOTICE.md](NOTICE.md)銆?- 鏈彃浠朵笌 DeepSeek 瀹樻柟鏃犻毝灞炲叧绯汇€?
