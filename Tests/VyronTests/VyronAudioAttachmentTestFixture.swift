import Foundation
import XCTest

enum VyronAudioAttachmentTestFixture {
    // A 440 Hz tone encoded as a small standalone MP3 fixture. No runtime encoder is required.
    static func mp3() throws -> Data {
        let encoded = """
            /+MYxAAK+I7FuUMAAqoFKLbQHd3d3P4iIifu7u//1wMDA3NQQOIg+D78EHXf4Y4DfpDHLv5zp93SJoc4WcQ3/GVEJRyhC3+D
            /+MYxA8QmUKQAZRQAG8H6ge5ABlxEnAPiYDmR1gd6mHvgGgCQCorCKC6//IR6KpEPh8ab//5CgNCUJA1/4lOg1W0AAWyC2TV
            /+MYxAcNwJ5yWdUAAvb//UZEWNiHBdIGzQGARIBhnpAY6EABwiDIw7ybIiXTnW/0f7f9///t+/1f//+v6SB///31WkXtMCCM
            /+MYxAsNsKY0KAa8RokjQJTj2DDAFLNt2gsz0A/zCdBCMDIAsoAKUTROVKw7D/p///////////+lzz/8MMMMM8/1hhzVSX29
            /+MYxA8PUL5oAVwQAGGFeNzTKEU1rgQMGJB4d8rpuE3mLQiDgfTWXLf+N555552MBofg4c1ghyjuGOUVJEkxwEslUl49jMDw
            /+MYxAwO2OqYAZRYACxrMkl+GKAt8A1rgBheUjJNHxmGgI5uTCejUz//7zQ3eCYkb/C4JiQLiv/iwuKiykxBTUU0LjCqqqqq
            /+MYxAsAAANIAcAAAKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
            """
        return try XCTUnwrap(Data(base64Encoded: encoded, options: .ignoreUnknownCharacters))
    }
}
