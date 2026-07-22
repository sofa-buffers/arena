// This is a generated file - do not edit.
//
// Generated from message.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Corresponds to full_scale_seq_struct_t
class FullScaleSeqStruct extends $pb.GeneratedMessage {
  factory FullScaleSeqStruct({
    $core.double? f32,
    $core.double? f64,
    $core.String? str,
    $core.List<$core.int>? bytesField,
  }) {
    final result = create();
    if (f32 != null) result.f32 = f32;
    if (f64 != null) result.f64 = f64;
    if (str != null) result.str = str;
    if (bytesField != null) result.bytesField = bytesField;
    return result;
  }

  FullScaleSeqStruct._();

  factory FullScaleSeqStruct.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FullScaleSeqStruct.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FullScaleSeqStruct',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fullscale'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'f32', fieldType: $pb.PbFieldType.OF)
    ..aD(2, _omitFieldNames ? '' : 'f64')
    ..aOS(3, _omitFieldNames ? '' : 'str')
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'bytesField', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FullScaleSeqStruct clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FullScaleSeqStruct copyWith(void Function(FullScaleSeqStruct) updates) =>
      super.copyWith((message) => updates(message as FullScaleSeqStruct))
          as FullScaleSeqStruct;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FullScaleSeqStruct create() => FullScaleSeqStruct._();
  @$core.override
  FullScaleSeqStruct createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FullScaleSeqStruct getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FullScaleSeqStruct>(create);
  static FullScaleSeqStruct? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get f32 => $_getN(0);
  @$pb.TagNumber(1)
  set f32($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasF32() => $_has(0);
  @$pb.TagNumber(1)
  void clearF32() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get f64 => $_getN(1);
  @$pb.TagNumber(2)
  set f64($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasF64() => $_has(1);
  @$pb.TagNumber(2)
  void clearF64() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get str => $_getSZ(2);
  @$pb.TagNumber(3)
  set str($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStr() => $_has(2);
  @$pb.TagNumber(3)
  void clearStr() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get bytesField => $_getN(3);
  @$pb.TagNumber(4)
  set bytesField($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBytesField() => $_has(3);
  @$pb.TagNumber(4)
  void clearBytesField() => $_clearField(4);
}

/// Corresponds to full_scale_seq_struct_of_fp_arrays_t
class FullScaleSeqStructOfFpArrays extends $pb.GeneratedMessage {
  factory FullScaleSeqStructOfFpArrays({
    $core.Iterable<$core.double>? fp32,
    $core.Iterable<$core.double>? fp64,
  }) {
    final result = create();
    if (fp32 != null) result.fp32.addAll(fp32);
    if (fp64 != null) result.fp64.addAll(fp64);
    return result;
  }

  FullScaleSeqStructOfFpArrays._();

  factory FullScaleSeqStructOfFpArrays.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FullScaleSeqStructOfFpArrays.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FullScaleSeqStructOfFpArrays',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fullscale'),
      createEmptyInstance: create)
    ..p<$core.double>(1, _omitFieldNames ? '' : 'fp32', $pb.PbFieldType.KF)
    ..p<$core.double>(2, _omitFieldNames ? '' : 'fp64', $pb.PbFieldType.KD)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FullScaleSeqStructOfFpArrays clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FullScaleSeqStructOfFpArrays copyWith(
          void Function(FullScaleSeqStructOfFpArrays) updates) =>
      super.copyWith(
              (message) => updates(message as FullScaleSeqStructOfFpArrays))
          as FullScaleSeqStructOfFpArrays;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FullScaleSeqStructOfFpArrays create() =>
      FullScaleSeqStructOfFpArrays._();
  @$core.override
  FullScaleSeqStructOfFpArrays createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FullScaleSeqStructOfFpArrays getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FullScaleSeqStructOfFpArrays>(create);
  static FullScaleSeqStructOfFpArrays? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.double> get fp32 => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<$core.double> get fp64 => $_getList(1);
}

/// Corresponds to full_scale_seq_struct_of_arrays_t
class FullScaleSeqStructOfArrays extends $pb.GeneratedMessage {
  factory FullScaleSeqStructOfArrays({
    $core.Iterable<$core.int>? u8,
    $core.Iterable<$core.int>? i8,
    $core.Iterable<$core.int>? u16,
    $core.Iterable<$core.int>? i16,
    $core.Iterable<$core.int>? u32,
    $core.Iterable<$core.int>? i32,
    $core.Iterable<$fixnum.Int64>? u64,
    $core.Iterable<$fixnum.Int64>? i64,
    FullScaleSeqStructOfFpArrays? nested,
  }) {
    final result = create();
    if (u8 != null) result.u8.addAll(u8);
    if (i8 != null) result.i8.addAll(i8);
    if (u16 != null) result.u16.addAll(u16);
    if (i16 != null) result.i16.addAll(i16);
    if (u32 != null) result.u32.addAll(u32);
    if (i32 != null) result.i32.addAll(i32);
    if (u64 != null) result.u64.addAll(u64);
    if (i64 != null) result.i64.addAll(i64);
    if (nested != null) result.nested = nested;
    return result;
  }

  FullScaleSeqStructOfArrays._();

  factory FullScaleSeqStructOfArrays.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FullScaleSeqStructOfArrays.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FullScaleSeqStructOfArrays',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fullscale'),
      createEmptyInstance: create)
    ..p<$core.int>(1, _omitFieldNames ? '' : 'u8', $pb.PbFieldType.KU3)
    ..p<$core.int>(2, _omitFieldNames ? '' : 'i8', $pb.PbFieldType.K3)
    ..p<$core.int>(3, _omitFieldNames ? '' : 'u16', $pb.PbFieldType.KU3)
    ..p<$core.int>(4, _omitFieldNames ? '' : 'i16', $pb.PbFieldType.K3)
    ..p<$core.int>(5, _omitFieldNames ? '' : 'u32', $pb.PbFieldType.KU3)
    ..p<$core.int>(6, _omitFieldNames ? '' : 'i32', $pb.PbFieldType.K3)
    ..p<$fixnum.Int64>(7, _omitFieldNames ? '' : 'u64', $pb.PbFieldType.KU6)
    ..p<$fixnum.Int64>(8, _omitFieldNames ? '' : 'i64', $pb.PbFieldType.K6)
    ..aOM<FullScaleSeqStructOfFpArrays>(10, _omitFieldNames ? '' : 'nested',
        subBuilder: FullScaleSeqStructOfFpArrays.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FullScaleSeqStructOfArrays clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FullScaleSeqStructOfArrays copyWith(
          void Function(FullScaleSeqStructOfArrays) updates) =>
      super.copyWith(
              (message) => updates(message as FullScaleSeqStructOfArrays))
          as FullScaleSeqStructOfArrays;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FullScaleSeqStructOfArrays create() => FullScaleSeqStructOfArrays._();
  @$core.override
  FullScaleSeqStructOfArrays createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FullScaleSeqStructOfArrays getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FullScaleSeqStructOfArrays>(create);
  static FullScaleSeqStructOfArrays? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.int> get u8 => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<$core.int> get i8 => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<$core.int> get u16 => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<$core.int> get i16 => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<$core.int> get u32 => $_getList(4);

  @$pb.TagNumber(6)
  $pb.PbList<$core.int> get i32 => $_getList(5);

  @$pb.TagNumber(7)
  $pb.PbList<$fixnum.Int64> get u64 => $_getList(6);

  @$pb.TagNumber(8)
  $pb.PbList<$fixnum.Int64> get i64 => $_getList(7);

  @$pb.TagNumber(10)
  FullScaleSeqStructOfFpArrays get nested => $_getN(8);
  @$pb.TagNumber(10)
  set nested(FullScaleSeqStructOfFpArrays value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasNested() => $_has(8);
  @$pb.TagNumber(10)
  void clearNested() => $_clearField(10);
  @$pb.TagNumber(10)
  FullScaleSeqStructOfFpArrays ensureNested() => $_ensure(8);
}

/// Corresponds to full_scale_seq_array_of_strings_t
class FullScaleSeqArrayOfStrings extends $pb.GeneratedMessage {
  factory FullScaleSeqArrayOfStrings({
    $core.Iterable<$core.String>? strings,
  }) {
    final result = create();
    if (strings != null) result.strings.addAll(strings);
    return result;
  }

  FullScaleSeqArrayOfStrings._();

  factory FullScaleSeqArrayOfStrings.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FullScaleSeqArrayOfStrings.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FullScaleSeqArrayOfStrings',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fullscale'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'strings')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FullScaleSeqArrayOfStrings clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FullScaleSeqArrayOfStrings copyWith(
          void Function(FullScaleSeqArrayOfStrings) updates) =>
      super.copyWith(
              (message) => updates(message as FullScaleSeqArrayOfStrings))
          as FullScaleSeqArrayOfStrings;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FullScaleSeqArrayOfStrings create() => FullScaleSeqArrayOfStrings._();
  @$core.override
  FullScaleSeqArrayOfStrings createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FullScaleSeqArrayOfStrings getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FullScaleSeqArrayOfStrings>(create);
  static FullScaleSeqArrayOfStrings? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get strings => $_getList(0);
}

/// Corresponds to full_scale_example_t
class FullScaleExample extends $pb.GeneratedMessage {
  factory FullScaleExample({
    $core.int? u8,
    $core.int? i8,
    $core.int? u16,
    $core.int? i16,
    $core.int? u32,
    $core.int? i32,
    $fixnum.Int64? u64,
    $fixnum.Int64? i64,
    FullScaleSeqStruct? nested,
    FullScaleSeqStructOfArrays? arrays,
    FullScaleSeqArrayOfStrings? stringArray,
  }) {
    final result = create();
    if (u8 != null) result.u8 = u8;
    if (i8 != null) result.i8 = i8;
    if (u16 != null) result.u16 = u16;
    if (i16 != null) result.i16 = i16;
    if (u32 != null) result.u32 = u32;
    if (i32 != null) result.i32 = i32;
    if (u64 != null) result.u64 = u64;
    if (i64 != null) result.i64 = i64;
    if (nested != null) result.nested = nested;
    if (arrays != null) result.arrays = arrays;
    if (stringArray != null) result.stringArray = stringArray;
    return result;
  }

  FullScaleExample._();

  factory FullScaleExample.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FullScaleExample.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FullScaleExample',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'fullscale'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'u8', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'i8')
    ..aI(3, _omitFieldNames ? '' : 'u16', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'i16')
    ..aI(5, _omitFieldNames ? '' : 'u32', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'i32')
    ..a<$fixnum.Int64>(7, _omitFieldNames ? '' : 'u64', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(8, _omitFieldNames ? '' : 'i64')
    ..aOM<FullScaleSeqStruct>(10, _omitFieldNames ? '' : 'nested',
        subBuilder: FullScaleSeqStruct.create)
    ..aOM<FullScaleSeqStructOfArrays>(100, _omitFieldNames ? '' : 'arrays',
        subBuilder: FullScaleSeqStructOfArrays.create)
    ..aOM<FullScaleSeqArrayOfStrings>(200, _omitFieldNames ? '' : 'stringArray',
        subBuilder: FullScaleSeqArrayOfStrings.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FullScaleExample clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FullScaleExample copyWith(void Function(FullScaleExample) updates) =>
      super.copyWith((message) => updates(message as FullScaleExample))
          as FullScaleExample;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FullScaleExample create() => FullScaleExample._();
  @$core.override
  FullScaleExample createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FullScaleExample getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FullScaleExample>(create);
  static FullScaleExample? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get u8 => $_getIZ(0);
  @$pb.TagNumber(1)
  set u8($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasU8() => $_has(0);
  @$pb.TagNumber(1)
  void clearU8() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get i8 => $_getIZ(1);
  @$pb.TagNumber(2)
  set i8($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasI8() => $_has(1);
  @$pb.TagNumber(2)
  void clearI8() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get u16 => $_getIZ(2);
  @$pb.TagNumber(3)
  set u16($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasU16() => $_has(2);
  @$pb.TagNumber(3)
  void clearU16() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get i16 => $_getIZ(3);
  @$pb.TagNumber(4)
  set i16($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasI16() => $_has(3);
  @$pb.TagNumber(4)
  void clearI16() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get u32 => $_getIZ(4);
  @$pb.TagNumber(5)
  set u32($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasU32() => $_has(4);
  @$pb.TagNumber(5)
  void clearU32() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get i32 => $_getIZ(5);
  @$pb.TagNumber(6)
  set i32($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasI32() => $_has(5);
  @$pb.TagNumber(6)
  void clearI32() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get u64 => $_getI64(6);
  @$pb.TagNumber(7)
  set u64($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasU64() => $_has(6);
  @$pb.TagNumber(7)
  void clearU64() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get i64 => $_getI64(7);
  @$pb.TagNumber(8)
  set i64($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasI64() => $_has(7);
  @$pb.TagNumber(8)
  void clearI64() => $_clearField(8);

  @$pb.TagNumber(10)
  FullScaleSeqStruct get nested => $_getN(8);
  @$pb.TagNumber(10)
  set nested(FullScaleSeqStruct value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasNested() => $_has(8);
  @$pb.TagNumber(10)
  void clearNested() => $_clearField(10);
  @$pb.TagNumber(10)
  FullScaleSeqStruct ensureNested() => $_ensure(8);

  @$pb.TagNumber(100)
  FullScaleSeqStructOfArrays get arrays => $_getN(9);
  @$pb.TagNumber(100)
  set arrays(FullScaleSeqStructOfArrays value) => $_setField(100, value);
  @$pb.TagNumber(100)
  $core.bool hasArrays() => $_has(9);
  @$pb.TagNumber(100)
  void clearArrays() => $_clearField(100);
  @$pb.TagNumber(100)
  FullScaleSeqStructOfArrays ensureArrays() => $_ensure(9);

  @$pb.TagNumber(200)
  FullScaleSeqArrayOfStrings get stringArray => $_getN(10);
  @$pb.TagNumber(200)
  set stringArray(FullScaleSeqArrayOfStrings value) => $_setField(200, value);
  @$pb.TagNumber(200)
  $core.bool hasStringArray() => $_has(10);
  @$pb.TagNumber(200)
  void clearStringArray() => $_clearField(200);
  @$pb.TagNumber(200)
  FullScaleSeqArrayOfStrings ensureStringArray() => $_ensure(10);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
