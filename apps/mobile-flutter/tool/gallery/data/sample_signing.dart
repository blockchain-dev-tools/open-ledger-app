import 'package:open_ledger_app/core/models/apdu_message.dart';

/// Sample pending sign request for the Transaction screen preview.
///
/// Represents an Ethereum EIP-1559 transfer with a decoded ERC-20 approve
/// action — the richest variant of the sign-approval UI.
final PendingSignRequest sampleSignRequest = PendingSignRequest(
  chainReviewId: 0,
  chain: 'ethereum',
  derivationPath: "m/44'/60'/0'/0/0",
  signingAddress: '0x71C7656EC7ab88b098defB751B7401B5f6d8976F',
  payloadHex:
      '02f9011f01843b9aca008504a817c8008252089471c7656ec7ab88b098defb751b7401b5f6d8976f80b844a9059cbb',
  parsedData: {
    'type': 'eth_tx',
    'chainId': '1',
    'to': '0x71C7656EC7ab88b098defB751B7401B5f6d8976F',
    'value': '1000000000000000000',
    'txType': 'eip1559',
    'gas': '21000',
    'gasPrice': '20000000000',
    'priorityFee': '1000000000',
    'nonce': '7',
    'action': {
      'method': 'approve',
      'params': [
        {
          'name': 'spender',
          'value': '0xdAC17F958D2ee523a2206206994597C13D831ec7',
          'type': 'address',
        },
        {
          'name': 'amount',
          'value': '5000000',
          'type': 'uint256',
        },
      ],
    },
  },
);

/// Sample pending sign result for the SignatureResult screen preview.
Map<String, dynamic> sampleSignResult() => {
      'isSuccess': true,
      'chain': 'ethereum',
      'type': 'eth_tx',
      'signingAddress': '0x71C7656EC7ab88b098defB751B7401B5f6d8976F',
      'derivationPath': "m/44'/60'/0'/0/0",
      'to': '0x71C7656EC7ab88b098defB751B7401B5f6d8976F',
      'value': '1000000000000000000',
      'signatureHex':
          '3044022079be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f8179802200c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5',
    };

/// Sample pending address request for the Address Confirm screen preview.
///
/// Mirrors an ETH GET_PUBLIC_KEY intercept (CLA 0xE0, INS 0x02) with P1=0x01
/// — the "show the address and wait for confirmation" flow.
final PendingAddressRequest sampleAddressRequest = PendingAddressRequest(
  chainReviewId: 0,
  chain: 'ethereum',
  derivationPath: "m/44'/60'/0'/0/0",
  address: '0x71C7656EC7ab88b098defB751B7401B5f6d8976F',
);
