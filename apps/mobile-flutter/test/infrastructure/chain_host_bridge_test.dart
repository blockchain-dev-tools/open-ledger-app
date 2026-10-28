/// Unit tests for [ChainHostBridge.parseReply].
///
/// The mapping is the only part of the FFI adapter that can run without loading
/// the native library, so it is exercised here against payloads copied from the
/// Rust side (`crates/open-ledger-ffi/src/chain_host.rs`).
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:open_ledger_app/core/models/chain_host_reply.dart';
import 'package:open_ledger_app/infrastructure/ffi/chain_host_bridge.dart';

const _address = '9858EfFD232B4033E47d90003D41EC34EcaEda94';

String reviewJson({String account = '"$_address"'}) =>
    '{"kind":"review","review_id":3,'
    '"action":{"type":"display_address","path":"m/44\'/60\'/0\'/0/0"},'
    '"document":{"operation":"address_confirmation",'
    '"network":{"name":"Ethereum","chain_id":1},'
    '"account":$account,"parse_status":"complete",'
    '"sections":[{"title_key":"review.section.address","fields":['
    '{"label_key":"review.field.address","value":'
    '{"type":"address","value":"$_address","network":"Ethereum",'
    '"role":"account"}}]}],"risks":[]}}';

void main() {
  group('emit replies', () {
    test('decodes the hex payload verbatim', () {
      final reply = ChainHostBridge.parseReply(
          '{"kind":"emit","exchange":1,"payload":"9000"}');

      expect(reply, isA<ChainHostEmit>());
      expect((reply as ChainHostEmit).payload, Uint8List.fromList([0x90, 0x00]));
    });

    test('rejects a payload that is not a string', () {
      expect(ChainHostBridge.parseReply('{"kind":"emit","payload":42}'), isNull);
    });
  });

  group('review replies', () {
    test('restores the 0x prefix and reads path/network', () {
      final reply = ChainHostBridge.parseReply(reviewJson());

      expect(reply, isA<ChainHostReview>());
      final review = reply as ChainHostReview;
      expect(review.reviewId, 3);
      expect(review.address, '0x$_address');
      expect(review.path, "m/44'/60'/0'/0/0");
      expect(review.network, 'Ethereum');
      expect(review.actionType, 'display_address');
      expect(review.isSign, isFalse);
      expect(review.document['operation'], 'address_confirmation');
    });

    test('recognises a signing review and reads its payload', () {
      const sign =
          '{"kind":"review","review_id":9,'
          '"action":{"type":"sign","operations":[{"operation_id":1,'
          '"public_parameters":{"payload_hex":"1901aabb"}}]},'
          '"document":{"operation":"transaction","network":{"name":"Ethereum",'
          '"chain_id":1},"account":"$_address","parse_status":"complete",'
          '"sections":[{"title_key":"review.section.transaction","fields":[]}],'
          '"risks":[]}}';

      final reply = ChainHostBridge.parseReply(sign);

      expect(reply, isA<ChainHostReview>());
      final review = reply as ChainHostReview;
      expect(review.isSign, isTrue);
      expect(review.payloadHex, '1901aabb');
      expect(review.sectionKind, 'review.section.transaction');
    });

    test('falls back to the section field when the account is absent', () {
      final reply = ChainHostBridge.parseReply(reviewJson(account: 'null'));

      expect(reply, isA<ChainHostReview>());
      expect((reply as ChainHostReview).address, '0x$_address');
    });

    test('returns null when no address can be displayed', () {
      const empty =
          '{"kind":"review","review_id":4,"action":{"type":"display_address",'
          '"path":"m/44\'/60\'/0\'/0\'/0"},"document":{"operation":'
          '"address_confirmation","network":{"name":"Ethereum","chain_id":1},'
          '"account":null,"parse_status":"complete","sections":[],"risks":[]}}';

      expect(ChainHostBridge.parseReply(empty), isNull);
    });

    test('returns null when review_id is missing', () {
      const noId = '{"kind":"review","document":{"account":"$_address"},'
          '"action":{"path":"m/44\'/60\'/0\'/0/0"}}';

      expect(ChainHostBridge.parseReply(noId), isNull);
    });

    test('keeps a base58 account address as-is', () {
      const solana =
          '{"kind":"review","review_id":5,"action":{"type":"sign",'
          '"operations":[]},"document":{"operation":"transaction",'
          '"network":{"name":"Solana","chain_id":null},'
          '"account":"9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",'
          '"parse_status":"partial","sections":'
          '[{"title_key":"review.section.solana","fields":[]}],"risks":[]}}';

      final review = ChainHostBridge.parseReply(solana) as ChainHostReview;
      expect(review.address, '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM');
      expect(review.sectionKind, 'review.section.solana');
    });
  });

  group('local account replies', () {
    String localJson(String payload) =>
        '{"kind":"local","request_id":1,"payload":"$payload"}';

    test('decodes the address and public key', () {
      const inner = '{"address":"0x9858EfFD232B4033E47d90003D41EC34EcaEda94",'
          '"public_key":"04aabb"}';
      final hex = inner.codeUnits
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      final material = ChainHostBridge.parseAccountMaterial(localJson(hex));
      expect(material, isNotNull);
      expect(material!.address, '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
      expect(material.publicKeyHex, '04aabb');
    });

    test('empty payload means the module refused', () {
      expect(ChainHostBridge.parseAccountMaterial(localJson('')), isNull);
    });

    test('a non-local reply is rejected', () {
      expect(
          ChainHostBridge.parseAccountMaterial('{"kind":"emit","payload":"9000"}'),
          isNull);
    });
  });

  group('bookkeeping replies', () {
    test('maps unknown kinds to a status', () {
      final reply = ChainHostBridge.parseReply(
          '{"kind":"finished","status":"delivered"}');

      expect(reply, isA<ChainHostStatus>());
      expect((reply as ChainHostStatus).kind, 'finished');
      expect(reply.status, 'delivered');
    });

    test('malformed JSON is rejected', () {
      expect(ChainHostBridge.parseReply('not json'), isNull);
    });
  });
}
