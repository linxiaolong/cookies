class_a {
    a number
    b number
    c boolean
    d string
}

class_b [number]

class_c {
    ref_a class_a
    ref_b class_b  
}

class_e <number, string>


class_f {
    a {
        b [number]
    }
    b [class_e]
    c {
        a number
        b string
        c {
            a number
            b [string]
            c <string, number>
        }
    }
}
