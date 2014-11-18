use GTK::Simple;
use GTK::GDK;
use Cairo;
use NativeCall;

gtk_simple_use_cairo;

sub MAIN($filename? is copy) {
    my GTK::Simple::App $app .= new: title => "Cairo Live-Coding environment";

    $app.border_width = 10;

    $app.set_content(
        GTK::Simple::VBox.new(
            GTK::Simple::HBox.new(
                GTK::Simple::VBox.new(
                    my $codeview = GTK::Simple::TextView.new(),
                    my $fps_toggle = GTK::Simple::ToggleButton.new(label => "slow mode"),
                ),
                my $da       = GTK::Simple::DrawingArea.new()
            ),
            my $statuslabel = GTK::Simple::Label.new(text => "ready when you are.")
        ));

    $app.size_request(800, 600);
    $codeview.size_request(400, 550);
    $da.size_request(400, 550);

    my &frame_handler = -> *@ { };

    my $animation_start_time;
    my $animation_last_t;
    my $animation_last_dt;

    my $last_working_code_text;

    $codeview.changed.stable(1).start(
        -> $widget {
            my $code = $widget.text;
            my &frame_callable;
            $statuslabel.text = "evaling the code now ...";
            try {
                &frame_callable = EVAL $code;

                CATCH {
                    say "error: $_";
                    $statuslabel.text = "Eval failed: $_"
                }
            }
            if defined &frame_callable {
                $statuslabel.text = "Evaluation finished.";
            }
            $last_working_code_text = $code;
            &frame_callable
        }).migrate.act(-> &frame_callable {
            &frame_handler = &frame_callable;
        });

    my $frame_number;
    my $fast_mode = True;

    $fps_toggle.toggled.act(-> $w { $fast_mode = not $w.status; say $fast_mode });

    $app.g_timeout(1000 / 25).act(
        -> @ ($t, $dt) {
            if ++$frame_number %% 4 or $fast_mode {
                $animation_last_t  = $t;
                $animation_last_dt = $dt;
                $da.queue_draw;
            }

            CATCH {
                say $_;
            }
        });

    $da.add_draw_handler(
        -> $widget, $ctx {
            try {
                frame_handler($ctx, $animation_last_t, $animation_last_dt);
                CATCH {
                    default {
                        &frame_handler = -> *@ { }
                        $statuslabel.text = "SORRY! $_";
                        say "Exception in frame handler:";
                        say $_;
                    }
                }
            }
        });

    if defined $filename and $filename.IO.e {
        $codeview.text = $filename.IO.slurp;
    } else  {
        $codeview.text = q:to/.../;
            sub frame($_, $t, $dt) {
                .scale(2, 2);
                .rgb(0, 0, 0);
                .rectangle(0, 0, 150, 150);
                .fill();
                .rgb(1, 0.75, 0.1);
                .move_to(sin($t) * 50 + 75, 50);
                .line_to(0, cos($t) * 50) :relative;
                .stroke();
            }
            ...
    }

    signal(SIGINT).tap(  { exit(); });
    #signal(SIGTERM).tap( { exit(); });

    $app.run();
    END {
        say "Thank you for playing.";
        $filename = "session-{now}.p6";
        $filename.IO.spurt($last_working_code_text);
        say "you can find the code in $filename";
    }
}
