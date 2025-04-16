// File: lib/src/doctrine/platforms/exception/platform_exceptions.dart

// Import the base Doctrine DBAL exception if it exists and is intended as a superclass,
// otherwise, just use Dart's base Exception.
// Assuming a base exception exists like this:
import '../../exceptions/doctrine_exceptions.dart';


/// Base marker interface or class for platform-related exceptions.
/// Allows catching all platform-specific logical errors.
/// Using an abstract class allows it to potentially extend DoctrineDbalException later if needed.
abstract class PlatformException implements DoctrineDbalException {
  // No specific members needed for a marker/base, but provides type hierarchy.
}

// --- Specific Platform Exceptions ---

/// Exception thrown when an invalid platform version string is specified.
/// Corresponds to Doctrine\DBAL\Platforms\Exception\InvalidPlatformVersion
class InvalidPlatformVersion extends DoctrineDbalException implements PlatformException {
  /// Creates a new instance for an invalid specified platform version.
  ///
  /// [version] The invalid platform version string provided.
  /// [expectedFormat] A description of the expected format.
  InvalidPlatformVersion(String version, String expectedFormat)
      : super(
            'Invalid platform version "$version" specified. The platform version has to be specified in the format: "$expectedFormat".');

  @override
  String toString() => 'InvalidPlatformVersion: $message';
}

/// Exception thrown when attempting to create a table without specifying any columns.
/// Corresponds to Doctrine\DBAL\Platforms\Exception\NoColumnsSpecifiedForTable
class NoColumnsSpecifiedForTable extends DoctrineDbalException implements PlatformException {
  /// Creates a new instance for a table missing column specifications.
  ///
  /// [tableName] The name of the table for which no columns were specified.
  NoColumnsSpecifiedForTable(String tableName)
      : super('No columns specified for table "$tableName".');

   @override
  String toString() => 'NoColumnsSpecifiedForTable: $message';
}

/// Exception thrown when a requested database feature or operation is not supported by the current platform.
/// Corresponds to Doctrine\DBAL\Platforms\Exception\NotSupported
class NotSupported extends DoctrineDbalException implements PlatformException {
  /// Creates a new instance indicating an unsupported operation.
  ///
  /// [featureOrMethod] A description of the feature or method name that is not supported.
  NotSupported(String featureOrMethod)
      : super('Operation "$featureOrMethod" is not supported by platform.');

  @override
  String toString() => 'NotSupported: $message';
}