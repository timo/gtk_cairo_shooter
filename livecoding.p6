use GTK::Simple;
use GTK::GDK;
use Cairo;
use NativeCall;

gtk_simple_use_cairo;

sub MAIN($filename?) {
    my GTK::Simple::App $app .= new: title => "Cairo Live-Coding environment";

    $app.set_content(
        GTK::Simple::VBox.new(
            GTK::Simple::HBox.new(
                my $codeview = GTK::Simple::TextView.new(),
                my $da       = GTK::Simple::DrawingArea.new()
            ),
            my $statuslabel = GTK::Simple::Label.new(text => "ready when you are.")
        ));

    $app.size_request(800, 600);
    $codeview.size_request(400, 550);
    $da.size_request(400, 550);

    my $frame_handler_channel = Channel.new();
    my &frame_handler = -> *@ { };

    my $animation_start_time;
    my $animation_last_t;
    my $animation_last_dt;

    $codeview.changed.stable(1).start(
        -> $widget {
            my $code = $widget.text;
            say "in code change handler";
            say $code.WHAT;
            my &frame_callable;
            GTK::Simple::Scheduler.cue( { $statuslabel.text = "evaling the code now ..." } );
            try {
                &frame_callable = EVAL $code;

                CATCH {
                    say "error: $_";
                    GTK::Simple::Scheduler.cue(
                        {
                            $statuslabel.text = "Eval failed: $_"
                        });
                }
            }
            if defined &frame_callable {
                GTK::Simple::Scheduler.cue( { $statuslabel.text = "Evaluation finished." } );
            }
            &frame_callable
        }).migrate.act(-> &frame_callable {
            $frame_handler_channel.send(&frame_callable);
        });

    $app.g_timeout(1000 / 30).act(
        -> @ ($t, $dt) {
            winner * {
                more $frame_handler_channel {
                    say "new frame code loading";
                    &frame_handler = $_;
                    $animation_start_time = $t;
                }
                wait 0 { Nil }
            };

            $animation_last_t  = $t;
            $animation_last_dt = $dt;
            $da.queue_draw;

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
            sub frame($cairo, $t, $dt) {
                $cairo.scale(2, 2);
                $cairo.rgb(0, 0, 0);
                $cairo.rectangle(0, 0, 150, 150);
                $cairo.fill();
                $cairo.rgb(1, 0.75, 0.1);
                $cairo.move_to(sin($t) * 50 + 75, 50);
                $cairo.line_to(0, cos($t) * 50) :relative;
                $cairo.stroke();
            }
            ...
    }

    signal(SIGINT).tap( {
        say "Thank you for playing.";
        my $filename = "session-{now}.p6";
        $filename.IO.spurt($codeview.text);
        say "you can find the code in $filename";
        exit();
    });

    $app.run();
    say "Thank you for playing.";
    my $filename = "session-{now}.p6";
    $filename.IO.spurt($codeview.text);
    say "you can find the code in $filename";
}
