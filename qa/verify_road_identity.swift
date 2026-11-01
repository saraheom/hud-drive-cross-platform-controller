import Foundation

@main
struct Verify {
    static func main() {
        let cases: [(String, String?, String?, Bool)] = [
            ("N Mascher St", "Mascher Street", nil, true),
            ("Roosevelt Expy", "Roosevelt Expressway", nil, true),
            ("North 2nd Street", "2nd St", nil, true),
            ("N Mascher St", "S Mascher St", nil, false),
            ("Roosevelt Expy", "Roosevelt Boulevard", nil, false),
            ("North 2nd St", "South 2nd Street", nil, false),
            ("East Market St", "West Market Street", nil, false),
            ("North 2nd St", "2nd Avenue", nil, false),
            ("N Broad St", "Broad Street", nil, true),
            ("Broad Street", "N Broad St", nil, true),
            ("US 1 North", nil, "US 1", true),
            ("Martin Luther King Jr Dr", "Martin Luther King Drive", nil, true),
            ("Roosevelt Expwy", "Roosevelt Expressway", nil, true),
            ("N Mascher St", nil, nil, false),
            ("", "Mascher Street", nil, false)
        ]
        for (route, name, ref, want) in cases {
            let got = CurrentNavRoadIdentity.routeRoadMatches(route, name: name, reference: ref)
            precondition(got == want, "FAIL route=\(route) name=\(name ?? "nil") ref=\(ref ?? "nil") got=\(got) expected=\(want)")
            print("PASS: \(route) vs \(name ?? ref ?? "nil") = \(got)")
        }
    }
}
