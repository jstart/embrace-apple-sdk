//
//  Copyright © 2024 Embrace Mobile, Inc. All rights reserved.
//

import Foundation
import EmbraceOTelInternal
import EmbraceSemantics

protocol SpanDataValidator {

    func validate(data: inout SpanData) -> Bool

}
