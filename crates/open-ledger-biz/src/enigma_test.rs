use super::*;

fn en(riddle: &str, secret: &str) -> String {
    generate(riddle, secret, Bip39Language::English).unwrap()
}

fn zh(riddle: &str, secret: &str) -> String {
    generate(riddle, secret, Bip39Language::ChineseSimplified).unwrap()
}

#[test]
fn same_input_produces_same_mnemonic() {
    let a = en("What is the answer to life?", "42");
    let b = en("What is the answer to life?", "42");
    assert_eq!(a, b);
}

#[test]
fn different_riddle_produces_different_mnemonic() {
    assert_ne!(en("abandon ability about", "test"), en("abandon ability above", "test"));
}

#[test]
fn different_secret_produces_different_mnemonic() {
    assert_ne!(en("test riddle", "secret A"), en("test riddle", "secret B"));
}

#[test]
fn deterministic_across_10_calls() {
    let reference = en("Satoshi Nakamoto", "Bitcoin");
    for _ in 0..10 {
        assert_eq!(en("Satoshi Nakamoto", "Bitcoin"), reference);
    }
}

#[test]
fn produces_24_words() {
    assert_eq!(en("hello", "world").split_whitespace().count(), 24);
}

#[test]
fn produces_valid_bip39_mnemonic() {
    let phrase = en("test", "test");
    assert!(Mnemonic::parse(&phrase).is_ok());
}

#[test]
fn empty_inputs_produce_deterministic_mnemonic() {
    assert_eq!(en("", ""), en("", ""));
}

#[test]
fn mixed_case_riddle_is_normalized() {
    assert_eq!(en("ABANDON ABILITY ABOUT", "test"), en("abandon ability about", "test"));
}

// ── 中文谜语（简体中文词表，CJK 逐字切分）──────────────────────────

#[test]
fn chinese_riddle_produces_24_words() {
    assert_eq!(zh("床前明月光", "1234").split_whitespace().count(), 24);
}

#[test]
fn chinese_riddle_is_deterministic() {
    let a = zh("床前明月光，疑是地上霜", "secret");
    let b = zh("床前明月光，疑是地上霜", "secret");
    assert_eq!(a, b);
}

#[test]
fn different_chinese_riddle_produces_different_mnemonic() {
    assert_ne!(zh("床前明月光", "secret"), zh("床前明月光，疑是地上霜", "secret"));
}

#[test]
fn chinese_riddle_sensitive_to_secret() {
    assert_ne!(zh("床前明月光", "key-A"), zh("床前明月光", "key-B"));
}

#[test]
fn chinese_mnemonic_is_valid_bip39() {
    assert!(Mnemonic::parse(&zh("人生得意须尽欢", "8888")).is_ok());
}

#[test]
fn chinese_wordlist_differs_from_english_for_same_text() {
    // 相同中文文本：简体中文词表能逐字匹配到汉字（贡献熵），英文词表匹配不到（熵仅来自密钥）
    let zh_mnemonic = generate("床前明月光", "secret", Bip39Language::ChineseSimplified).unwrap();
    let en_mnemonic = generate("床前明月光", "secret", Bip39Language::English).unwrap();
    assert_ne!(zh_mnemonic, en_mnemonic);
}

// ── 步骤化拆解（与 JS riddle.test.ts 相同测试向量）─────────────────
//
// 链：match_tokens → tokens_to_indices → indices_to_bytes → finalize_entropy
// 英文向量 abandon ability about（索引 0,1,3）+ 密钥 test；
// 中文向量 床前明月光（索引 1051,114,143,168,263）+ 密钥 1234。

#[test]
fn step1_match_tokens_english() {
    let tokens = match_tokens("abandon ability about", Language::English);
    assert_eq!(tokens, vec!["abandon".to_string(), "ability".to_string(), "about".to_string()]);
}

#[test]
fn step1_match_tokens_skips_unknown_word() {
    let tokens = match_tokens("abandon zzz about", Language::English);
    assert_eq!(tokens, vec!["abandon".to_string(), "about".to_string()]);
}

#[test]
fn step2_tokens_to_indices_english() {
    let tokens = vec!["abandon".to_string(), "ability".to_string(), "about".to_string()];
    assert_eq!(tokens_to_indices(&tokens, Language::English), vec![0, 1, 3]);
}

#[test]
fn step3_indices_to_bytes_english() {
    // 每词 2 字节大端按顺序拼接，长度随词数变（不再补零）
    let bytes = indices_to_bytes(&[0, 1, 3]);
    assert_eq!(hex::encode(bytes), "000000010003");
}

#[test]
fn step4_finalize_entropy_english() {
    let bytes = indices_to_bytes(&[0, 1, 3]);
    assert_eq!(
        hex::encode(finalize_entropy(&bytes, "test")),
        "2c62100bfb996b03f3379a5e0d796e6ed62a9f7657649780fb08fc3fde72cecb"
    );
}

#[test]
fn step1_match_tokens_chinese() {
    let tokens = match_tokens("床前明月光", Language::SimplifiedChinese);
    assert_eq!(
        tokens,
        vec!["床".to_string(), "前".to_string(), "明".to_string(), "月".to_string(), "光".to_string()]
    );
}

#[test]
fn step2_tokens_to_indices_chinese() {
    let tokens = vec!["床".to_string(), "前".to_string(), "明".to_string(), "月".to_string(), "光".to_string()];
    assert_eq!(tokens_to_indices(&tokens, Language::SimplifiedChinese), vec![1051, 114, 143, 168, 263]);
}

#[test]
fn step3_indices_to_bytes_chinese() {
    // 每词 2 字节大端按顺序拼接：04 1b | 00 72 | 00 8f | 00 a8 | 01 07
    let bytes = indices_to_bytes(&[1051, 114, 143, 168, 263]);
    assert_eq!(hex::encode(bytes), "041b0072008f00a80107");
}

#[test]
fn step4_finalize_entropy_chinese() {
    let bytes = indices_to_bytes(&[1051, 114, 143, 168, 263]);
    assert_eq!(
        hex::encode(finalize_entropy(&bytes, "1234")),
        "d8b3a4adf26bcbdac6500e1d253dafaa096836a1d565c5a70986831091afe95e"
    );
}

// ── 最终助记词（生成器全链路输出，便于与 TS/web 实现比对）──────────────

#[test]
fn final_mnemonic_english_vector() {
    assert_eq!(
        en("abandon ability about", "test"),
        "cluster awesome actual warm note limit smoke viable fun hint fortune tank glance exile sun uncle nurse amazing season wear worth defense depth idea"
    );
}

#[test]
fn final_mnemonic_chinese_short() {
    assert_eq!(
        zh("床前明月光", "1234"),
        "suffer outdoor clock tooth royal uniform bone achieve brush clarify hip favorite notable brave mansion protect shield debate giant alert animal subject pistol seat"
    );
}

#[test]
fn long_chinese_riddle_skips_unmatched() {
    // 《静夜思》：标点「，」「。」被跳过，「霜」不在简中词表被跳过，
    // 19 个命中字全部参与熵（未超过 48 上限）
    let tokens = match_tokens("床前明月光，疑是地上霜。举头望明月，低头思故乡。", Language::SimplifiedChinese);
    assert_eq!(tokens.len(), 19);
    assert_eq!(tokens.join(""), "床前明月光疑是地上举头望明月低头思故乡");
}

#[test]
fn long_chinese_riddle_full_pipeline() {
    let riddle = "床前明月光，疑是地上霜。举头望明月，低头思故乡。";
    let tokens = match_tokens(riddle, Language::SimplifiedChinese);
    let indices = tokens_to_indices(&tokens, Language::SimplifiedChinese);
    assert_eq!(indices, vec![1051, 114, 143, 168, 263, 1357, 2, 27, 13, 528, 212, 522, 143, 168, 384, 212, 289, 611, 941]);

    let bytes = indices_to_bytes(&indices);
    assert_eq!(
        hex::encode(&bytes),
        "041b0072008f00a80107054d0002001b000d021000d4020a008f00a8018000d40121026303ad"
    );
    assert_eq!(
        hex::encode(finalize_entropy(&bytes, "1234")),
        "852be79f9f24282c0ec602efc0080625d088f09c3da2dc86b0c538ea4bc0f5ca"
    );
    // 步骤组合等价于 derive_entropy 全链路
    assert_eq!(
        hex::encode(derive_entropy(riddle, "1234", Language::SimplifiedChinese)),
        "852be79f9f24282c0ec602efc0080625d088f09c3da2dc86b0c538ea4bc0f5ca"
    );
    // 全链路最终助记词（《静夜思》全文 + 密钥 1234）
    assert_eq!(
        zh(riddle, "1234"),
        "lunch game tree dinner dream bid deposit scare used able account entry ancient joke ill reform symptom culture course impact pigeon there strong expect"
    );
}

#[test]
fn long_riddle_over_100_chars_uses_first_48_matches() {
    // 《将进酒》204 个 token（> 100），「樽」「馔」等生僻字不在词表被跳过，
    // 命中 159 个，只取前 48 个命中字参与熵
    let riddle = "君不见黄河之水天上来，奔流到海不复回。君不见高堂明镜悲白发，朝如青丝暮成雪。人生得意须尽欢，莫使金樽空对月。天生我材必有用，千金散尽还复来。烹羊宰牛且为乐，会须一饮三百杯。岑夫子，丹丘生，将进酒，杯莫停。与君歌一曲，请君为我倾耳听。钟鼓馔玉不足贵，但愿长醉不复醒。古来圣贤皆寂寞，惟有饮者留其名。陈王昔时宴平乐，斗酒十千恣欢谑。主人何为言少钱，径须沽取对君酌。五花马，千金裘，呼儿将出换美酒，与尔同销万古愁。";

    let tokens = match_tokens(riddle, Language::SimplifiedChinese);
    assert_eq!(tokens.len(), 48);
    assert_eq!(tokens.join(""), "君不见黄河之水天上来奔流到海不复回君不见高堂明镜悲白发朝如青丝成雪人生得意须尽欢莫使金空对月天生");

    let indices = tokens_to_indices(&tokens, Language::SimplifiedChinese);
    assert_eq!(indices, vec![1135, 4, 228, 511, 550, 65, 76, 116, 13, 21, 1464, 216, 25, 275, 4, 390, 253, 1135, 4, 228, 78, 1017, 143, 1341, 1506, 313, 37, 577, 75, 412, 708, 33, 1085, 8, 24, 61, 166, 393, 662, 819, 1298, 95, 283, 354, 32, 168, 116, 24]);
    let bytes = indices_to_bytes(&indices);
    assert_eq!(
        hex::encode(&bytes),
        "046f000400e401ff02260041004c0074000d001505b800d8001901130004018600fd046f000400e4004e03f9008f053d05e2013900250241004b019c02c40021043d00080018003d00a60189029603330512005f011b0162002000a800740018"
    );
    assert_eq!(
        hex::encode(finalize_entropy(&bytes, "1234")),
        "b045bcbc7e8dfdebe46ab7c57061507f643d33d51cb8b7c6ef16083eec0a5f3d"
    );

    // 长文本结果 == 前 48 个命中字结果（第 49 个命中字起不影响）
    let short = tokens.join("");
    assert_eq!(
        derive_entropy(riddle, "1234", Language::SimplifiedChinese),
        derive_entropy(&short, "1234", Language::SimplifiedChinese)
    );
    // 全链路最终助记词（《将进酒》全文 + 密钥 1234）
    assert_eq!(
        zh(riddle, "1234"),
        "raccoon combine congress wonder thank vote museum finger shell loan favorite yard duck okay federal novel result danger sheriff away uphold ahead language rally"
    );
}