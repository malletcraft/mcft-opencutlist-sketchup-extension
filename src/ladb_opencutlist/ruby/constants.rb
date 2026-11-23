module Ladb::OpenCutList

    EXTENSION_NAME = 'OpenCutList (MCFT Edition)'.freeze
    # Ends in a digit, so IS_LAB stays false (docs/mcft/MOP-ON-OCL8.md §2.3).
    EXTENSION_VERSION = '8.0.0-lab.mcft.1'.freeze
    # UPSTREAM'S BUILD, BYTE FOR BYTE. The dialog's JS carries it too (from the
    # rbz) and locks itself into the "zzz" layout when the two differ.
    EXTENSION_BUILD = '202611191727'.freeze

    DEFAULT_LANGUAGE = 'en'
    ENABLED_LANGUAGES = %w[bg cs de en es fr hu it nl pl pt ro ru uk vi zh]

    FILE_FORMAT_SKP = 'skp'.freeze
    FILE_FORMAT_STL = 'stl'.freeze
    FILE_FORMAT_OBJ = 'obj'.freeze
    FILE_FORMAT_DXF = 'dxf'.freeze
    FILE_FORMAT_SVG = 'svg'.freeze

end
