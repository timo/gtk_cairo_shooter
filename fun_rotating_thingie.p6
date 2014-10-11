sub frame($cairo, $t, $dt) {
    $cairo.scale(5, 5);
    $cairo.rgb(0, 0, 0);
    $cairo.rectangle(0, 0, 150, 150);
    $cairo.fill();

    $cairo.rgb(1, 0.75, 0.1);
    my @positions = do for ^12 {
        my num $x = sin($t + $_ / 2) * 50 + 75;
        my num $y = cos($t + $_ / 2) * 50 + 75;
        $cairo.move_to($x, 75);
        $cairo.line_to($x, $y);
        $x, $y;
    }
    $cairo.stroke();

    $cairo.rgb(1, 1, 1);
    for @positions -> num $x1, num $y1, num $x2, num $y2 {
        my num $midy = ($y1 + $y2) / 2;
        $cairo.move_to($x1, $y1);
        $cairo.line_to($x1, $midy);
        $cairo.line_to($x2, $midy);
        $cairo.line_to($x2, $y2);
    }
    $cairo.stroke();

    $cairo.rgb(1, 0.75, 0.1);
    $cairo.move_to(25, 75);
    $cairo.line_to(100, 0) :relative;
    $cairo.stroke();

    $cairo.rgb(sin($t) * 0.5 + 0.5, cos($t) * 0.5 + 0.5, 0);
    for @positions -> num $x, num $y {
        $cairo.rectangle($x - 5, $y - 5, 10, 10);
        $cairo.fill();
    }
}
