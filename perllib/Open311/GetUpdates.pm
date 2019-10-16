package Open311::GetUpdates;

use Moo;
use Open311;
use FixMyStreet::Cobrand;

has body_list => ( is => 'ro' );
has system_user => ( is => 'ro' );

sub get_updates {
    my $self = shift;

    while ( my $body = $self->body_list->next ) {
        my $open311 = Open311->new(
            endpoint     => $body->endpoint,
            jurisdiction => $body->jurisdiction,
            api_key      => $body->api_key
        );

        my $reports = $body->result_source->schema->resultset('Problem')->to_body($body)->search(
            {
                state => { 'IN', [qw/confirmed fixed/] },
                -and => [
                    external_id => { '!=', undef },
                    external_id => { '!=', '' },
                ],
            }
        );

        my @report_ids = ();
        while ( my $report = $reports->next ) {
            push @report_ids, $report->external_id;
        }

        next unless @report_ids;

        $self->update_reports( \@report_ids, $open311, $body );
    }
}

sub update_reports {
    my ( $self, $report_ids, $open311, $body ) = @_;

    my $service_requests = $open311->get_service_requests( { report_ids => $report_ids } );
    my $requests = $service_requests->{request};

    for my $request (@$requests) {
        # if there's no updated date then we can't
        # tell if it's newer than what we have so we should skip it
        next unless $request->{updated_datetime};

        my $request_id = $request->{service_request_id};

        my $problem = $body->result_source->schema->resultset('Problem')
          ->search( { external_id => $request_id, } );

        if (my $p = $problem->first) {
            my $cobrand = FixMyStreet::Cobrand->get_class_for_moniker($p->cobrand)->new();
            $cobrand->set_lang_and_domain($p->lang, 1, FixMyStreet->path_to('locale')->stringify );
            $p->update_from_open311_service_request( $request, $body, $self->system_user );
        }
    }

    return 1;
}

1;
