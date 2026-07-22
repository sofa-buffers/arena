// This is a generated file - do not edit.
//
// Generated from message.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use fullScaleSeqStructDescriptor instead')
const FullScaleSeqStruct$json = {
  '1': 'FullScaleSeqStruct',
  '2': [
    {'1': 'f32', '3': 1, '4': 1, '5': 2, '10': 'f32'},
    {'1': 'f64', '3': 2, '4': 1, '5': 1, '10': 'f64'},
    {'1': 'str', '3': 3, '4': 1, '5': 9, '10': 'str'},
    {'1': 'bytes_field', '3': 4, '4': 1, '5': 12, '10': 'bytesField'},
  ],
};

/// Descriptor for `FullScaleSeqStruct`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fullScaleSeqStructDescriptor = $convert.base64Decode(
    'ChJGdWxsU2NhbGVTZXFTdHJ1Y3QSEAoDZjMyGAEgASgCUgNmMzISEAoDZjY0GAIgASgBUgNmNj'
    'QSEAoDc3RyGAMgASgJUgNzdHISHwoLYnl0ZXNfZmllbGQYBCABKAxSCmJ5dGVzRmllbGQ=');

@$core.Deprecated('Use fullScaleSeqStructOfFpArraysDescriptor instead')
const FullScaleSeqStructOfFpArrays$json = {
  '1': 'FullScaleSeqStructOfFpArrays',
  '2': [
    {'1': 'fp32', '3': 1, '4': 3, '5': 2, '10': 'fp32'},
    {'1': 'fp64', '3': 2, '4': 3, '5': 1, '10': 'fp64'},
  ],
};

/// Descriptor for `FullScaleSeqStructOfFpArrays`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fullScaleSeqStructOfFpArraysDescriptor =
    $convert.base64Decode(
        'ChxGdWxsU2NhbGVTZXFTdHJ1Y3RPZkZwQXJyYXlzEhIKBGZwMzIYASADKAJSBGZwMzISEgoEZn'
        'A2NBgCIAMoAVIEZnA2NA==');

@$core.Deprecated('Use fullScaleSeqStructOfArraysDescriptor instead')
const FullScaleSeqStructOfArrays$json = {
  '1': 'FullScaleSeqStructOfArrays',
  '2': [
    {'1': 'u8', '3': 1, '4': 3, '5': 13, '10': 'u8'},
    {'1': 'i8', '3': 2, '4': 3, '5': 5, '10': 'i8'},
    {'1': 'u16', '3': 3, '4': 3, '5': 13, '10': 'u16'},
    {'1': 'i16', '3': 4, '4': 3, '5': 5, '10': 'i16'},
    {'1': 'u32', '3': 5, '4': 3, '5': 13, '10': 'u32'},
    {'1': 'i32', '3': 6, '4': 3, '5': 5, '10': 'i32'},
    {'1': 'u64', '3': 7, '4': 3, '5': 4, '10': 'u64'},
    {'1': 'i64', '3': 8, '4': 3, '5': 3, '10': 'i64'},
    {
      '1': 'nested',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.fullscale.FullScaleSeqStructOfFpArrays',
      '10': 'nested'
    },
  ],
};

/// Descriptor for `FullScaleSeqStructOfArrays`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fullScaleSeqStructOfArraysDescriptor = $convert.base64Decode(
    'ChpGdWxsU2NhbGVTZXFTdHJ1Y3RPZkFycmF5cxIOCgJ1OBgBIAMoDVICdTgSDgoCaTgYAiADKA'
    'VSAmk4EhAKA3UxNhgDIAMoDVIDdTE2EhAKA2kxNhgEIAMoBVIDaTE2EhAKA3UzMhgFIAMoDVID'
    'dTMyEhAKA2kzMhgGIAMoBVIDaTMyEhAKA3U2NBgHIAMoBFIDdTY0EhAKA2k2NBgIIAMoA1IDaT'
    'Y0Ej8KBm5lc3RlZBgKIAEoCzInLmZ1bGxzY2FsZS5GdWxsU2NhbGVTZXFTdHJ1Y3RPZkZwQXJy'
    'YXlzUgZuZXN0ZWQ=');

@$core.Deprecated('Use fullScaleSeqArrayOfStringsDescriptor instead')
const FullScaleSeqArrayOfStrings$json = {
  '1': 'FullScaleSeqArrayOfStrings',
  '2': [
    {'1': 'strings', '3': 1, '4': 3, '5': 9, '10': 'strings'},
  ],
};

/// Descriptor for `FullScaleSeqArrayOfStrings`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fullScaleSeqArrayOfStringsDescriptor =
    $convert.base64Decode(
        'ChpGdWxsU2NhbGVTZXFBcnJheU9mU3RyaW5ncxIYCgdzdHJpbmdzGAEgAygJUgdzdHJpbmdz');

@$core.Deprecated('Use fullScaleExampleDescriptor instead')
const FullScaleExample$json = {
  '1': 'FullScaleExample',
  '2': [
    {'1': 'u8', '3': 1, '4': 1, '5': 13, '10': 'u8'},
    {'1': 'i8', '3': 2, '4': 1, '5': 5, '10': 'i8'},
    {'1': 'u16', '3': 3, '4': 1, '5': 13, '10': 'u16'},
    {'1': 'i16', '3': 4, '4': 1, '5': 5, '10': 'i16'},
    {'1': 'u32', '3': 5, '4': 1, '5': 13, '10': 'u32'},
    {'1': 'i32', '3': 6, '4': 1, '5': 5, '10': 'i32'},
    {'1': 'u64', '3': 7, '4': 1, '5': 4, '10': 'u64'},
    {'1': 'i64', '3': 8, '4': 1, '5': 3, '10': 'i64'},
    {
      '1': 'nested',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.fullscale.FullScaleSeqStruct',
      '10': 'nested'
    },
    {
      '1': 'arrays',
      '3': 100,
      '4': 1,
      '5': 11,
      '6': '.fullscale.FullScaleSeqStructOfArrays',
      '10': 'arrays'
    },
    {
      '1': 'string_array',
      '3': 200,
      '4': 1,
      '5': 11,
      '6': '.fullscale.FullScaleSeqArrayOfStrings',
      '10': 'stringArray'
    },
  ],
};

/// Descriptor for `FullScaleExample`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fullScaleExampleDescriptor = $convert.base64Decode(
    'ChBGdWxsU2NhbGVFeGFtcGxlEg4KAnU4GAEgASgNUgJ1OBIOCgJpOBgCIAEoBVICaTgSEAoDdT'
    'E2GAMgASgNUgN1MTYSEAoDaTE2GAQgASgFUgNpMTYSEAoDdTMyGAUgASgNUgN1MzISEAoDaTMy'
    'GAYgASgFUgNpMzISEAoDdTY0GAcgASgEUgN1NjQSEAoDaTY0GAggASgDUgNpNjQSNQoGbmVzdG'
    'VkGAogASgLMh0uZnVsbHNjYWxlLkZ1bGxTY2FsZVNlcVN0cnVjdFIGbmVzdGVkEj0KBmFycmF5'
    'cxhkIAEoCzIlLmZ1bGxzY2FsZS5GdWxsU2NhbGVTZXFTdHJ1Y3RPZkFycmF5c1IGYXJyYXlzEk'
    'kKDHN0cmluZ19hcnJheRjIASABKAsyJS5mdWxsc2NhbGUuRnVsbFNjYWxlU2VxQXJyYXlPZlN0'
    'cmluZ3NSC3N0cmluZ0FycmF5');
