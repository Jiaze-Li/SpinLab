import Foundation

/// The one definition of the New Sample form's fields (which fields exist, their labels, units,
/// numeric tag names and which are required). The desktop window draws itself from it, and the
/// publish script copies it into the phone page's data, so both entrances ask for the same things.
/// Option lists (lab, materials, substrate) are not here: they always come from the Rules Book.
struct NewSampleFormSchema: Decodable, Equatable {
    struct Required: Decodable, Equatable {
        var key: String
        var label: String
    }

    struct NumberField: Decodable, Equatable, Identifiable {
        var key: String
        var tag: String
        var label: String
        var unit: String
        var placeholder: String?

        var id: String { key }
        /// "Temperature (°C)"; the unit is only a label, SpinLab adds the real unit when it builds the tag.
        var displayLabel: String { unit.isEmpty ? label : "\(label) (\(unit))" }
    }

    struct RheedField: Decodable, Equatable, Identifiable {
        var key: String
        var label: String
        var metadataKey: String

        var id: String { key }
    }

    var version: Int
    var required: [Required]
    var numberFields: [NumberField]
    var rheedFields: [RheedField]

    static let shared: NewSampleFormSchema = {
        guard let url = Bundle.spinLabConfig.url(forResource: "new_sample_form_schema", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let schema = try? JSONDecoder().decode(NewSampleFormSchema.self, from: data)
        else {
            preconditionFailure("new_sample_form_schema.json is missing from the app bundle or unreadable.")
        }
        return schema
    }()
}
