package MBmaint::DSmeta;
use Moose;
use strict;
use warnings;
use Data::Dumper;
use MBmaint::DButil;
use Template;
use XML::LibXML;

# Attributes of the DSM object
has 'dataset'       => ( is => 'rw', isa => 'HashRef' );
has 'dbUtil'        => ( is => 'rw', isa => 'Object' );
has 'verbose'       => ( is => 'rw', isa => 'Int' );

my $configFilename = "/Users/peter/Projects/MSI/LTER/MBmaint/config/MBmaint.ini";
my $TEMPLATE_DIR = "/Users/peter/Projects/MSI/LTER/MBmaint/templates/";

my $DEFAULT_ROW_ACTION = "update";

sub BUILD {
    my $self = shift;

    $self->dbUtil(MBmaint::DButil->new({configFile => $configFilename, verbose => $self->verbose }));
}

sub DEMOLISH {
    my $self = shift;
}

sub loadXML {

    # Populate the DSMeta data structure from an XML document.

    my $self = shift;
    my $dataFilename = shift;
    my $verbose = shift;

    my $attr;
    my $attrName;
    my $attributeRef;
    my $dom;
    my $href;
    my @tableNodes;
    my @rowNodes;
    my @childNodes;
    my $dataset = {};
    my $sth;

    my @actions = ();
    my $firstRow; 
    my @colNames = (); 
    my @colValues = ();
    my $fn;
    my $nodemap;
    my $node;
    my @tmpArr;
    my %tableKeys;
    #my @keyColumns;
    my $keyColumnsRef;
    my $tableName;

    # Internal datastructure example. The 'names' list is the names
    # of the database columns. The 'values' list contains the database
    # values, in the same order as the 'names'.
    #
    # $dataset = {
    #          'DatasetPersonnel' => {
    #                            'names' => [
    #                                           'DataSetID',
    #                                           'NameID',
    #                                           'AuthorshipOrder',
    #                                           'AuthorshipRole'
    #                                       ],
    #                            'values' => [
    #                                          [
    #                                            '10',
    #                                            'sbclter',
    #                                            '1',
    #                                            'creator'
    #                                          ],
    #                                          [
    #                                            '10',
    #                                            'lwashburn',
    #                                            '2',
    #                                            'creator'
    #                                          ]
    #                                        ]
    #                            'actions' => [ 'update',
    #                                           'delete' ]
    #                          }
    #    };
    
    # sample XML data file:
    # <MB_content task="tsud" datasetid="10">
    #  <table name="DatasetPersonnel">
    #    <row>
    #      <column name="DataSetID">10</column>
    #      <column name="NameID">sbclter</column>
    #      <column name="AuthorshipOrder">1</column>
    #      <column name="AuthorshipRole">creator</column>
    #    </row>
    #    <row action="delete">
    #      <column name="DataSetID">10</column>
    #      <column name="NameID>lwashburn"</column>
    #      <column name="AuthorshipOrder">2</column>
    #      <column name="AuthorshipRole">creator</column>
    #    </row>
    #  </table>
    # </MB_content>

    # Create a DOM from the XML document that contains the data to send to Metabase 
    print STDERR "Reading XML file: " . $dataFilename . "\n", if $verbose;
    $dom = XML::LibXML->load_xml(location => $dataFilename, { no_blanks => 1 });

    # Find <table> entries. There may be data for multiple tables.
    @tableNodes = $dom->findnodes("/metabase2_content/table");

    # Loop through each table in the input XML, accumulating data in order to build our 
    # internal data structure.
    for my $n (@tableNodes) {
        $firstRow = 1;
        # attributes of the XML element "table"
        $tableName = $n->getAttribute("name");
        # Top level hash element of internal data structure is the name of the table, i.e. "DataSetPersonnel"
        $dataset->{$tableName} = {};

        $keyColumnsRef = $self->dbUtil->getKeyColumns($tableName);
        #DBI::dump_results($href);

        @{$dataset->{$tableName}{'keyColumns'}} = @$keyColumnsRef;
    
        # Get the row elements 
        @rowNodes = $n->getChildrenByTagName("row");
        # Loop through rows
        my $action;
        for my $r (@rowNodes) {
            $action = $r->getAttribute("action");
            $action = $DEFAULT_ROW_ACTION, if (not defined $action or $action eq "");
            push(@actions, $action);
            # Get the field names
            @childNodes = $r->getChildrenByTagName("column");
            # Loop through fields (columns)
            # The <column> elements can have an optional 'src="file"' attribute. If this is
            # present, then the text value of this element is the name of a file to read, where
            # the contents of the file will be used as the text value, for example:
            #     <column name="MethodStep_xml" src="file">ds10_methods.xml</column>
            for my $c (@childNodes) {
                # If this is the first row that we have processed, then save the column name
                if ($firstRow) {
                    push(@colNames, $c->getAttribute("name"));
                }

                # The column value can come from the XML text field of the input XML file, or if
                # the attribute "src=<file>" is set, then the value will be the entire contents
                # of the filename that is in the XML text field, i.e.
                #
                #      <column name="MethodStep_xml" src="file">ds10_methods.xml</column>
                my $srcType = $c->getAttribute("src");
                if (not defined $srcType) {
                    push(@colValues, $c->textContent);
                }
                elsif (lc($srcType) eq "file") {
                    my $fn = $c->textContent; 
                    my $fh; 
                    open($fh, '<', $fn) or die "Can't open file: " . $fn . "\n";
                    my $content = join('', <$fh>);   
                    push(@colValues, $content);
                    close($fh);
                } elsif ($srcType ne "") {
                    die "unknown src type file: " . $dataFilename . ", element: " . $c->getName();
                }
            }

            # Record database column names and values to our internal data structure. Only record the names once, i.e. for the
            # first row.
            if ($firstRow) {
                @{$dataset->{$tableName}{'names'}} = @colNames;
                push(@{$dataset->{$tableName}{'values'}}, [ @colValues ]);
                $firstRow = 0;
            } else {
                push(@{$dataset->{$tableName}{'values'}},  [ @colValues ]);
            }

            @colNames = (); 
            @colValues = ();
        }

        @{$dataset->{$tableName}{'actions'}} = @actions;
        @actions = ();
    }

    #print Dumper($dataset);
    $self->dataset($dataset);
}

sub sendToDB {

    # Send the internal representation of the dataset metadata to the database.

    my $self = shift;
    my $verbose = shift;

    my $action;
    my $href;
    my @keyColumns;
    my @colNames;
    my @rowActions;
    my @rowValues;
    my @colValues;
    my $v;

    # Top level keys are the table names.
    my @tables = keys(%{$self->dataset});
    for my $tableName (@tables) {
        #print "table: " . "$tableName" . "\n";

        $href = $self->dataset->{$tableName};
        @keyColumns = @{$href->{'keyColumns'}};

        @colNames = @{$href->{'names'}};
        @rowValues = @{$href->{'values'}};
        @rowActions = @{$href->{'actions'}};

        my $i;
        # Loop through the data set metadata and send one row at a time.
        # of data to metabase at a time.
        for ($i = 0 ; $i < scalar(@rowValues); $i++) {
            @colValues = @{$rowValues[$i]};

            # Determine the requested action for this row (update, delete). If not specified, update is the default (see $DEFAULT_ROW_ACTION)
            $action = $rowActions[$i];
            $self->dbUtil->sendRow($tableName, \@keyColumns, \@colNames, \@colValues, $action, $verbose);
        }
    }
   
    # Commit the transaction, close the database.
    $self->dbUtil->closeDB($verbose);

    return;
}

sub listTemplates {
    my $self = shift;

    opendir(DIR, $TEMPLATE_DIR) or die "Can't open $TEMPLATE_DIR";
    my @files = sort (grep(/query_pg_/, readdir(DIR)));

    for my $f (@files) {
        $f =~ s/query_pg_//;
        $f =~ s/.tt//;
        print STDERR $f . "\n";
    }
}

sub exportXML {

    # Run one of Margaret's famous XML SQL script's to extract dataset metadata from PostgreSQL
    # and export it to XML.
    my $self = shift;
    my $taskName = shift;
    my $datasetId = shift;
    my $verbose = shift;

    my $doc;
    my $output;
    my $dsXML;
    my $templateName;
    my %templateVars;

    # Template files in the ./templates directory have the format
    # 'query_pg_'<task name>'.tt', for example:
    # 
    #     query_pg_DataSetMethods.tt
    #
    $templateName = $TEMPLATE_DIR . 'query_pg_' . $taskName . ".tt";
    $templateVars{'datasetid'} = $datasetId;

    my $tt = Template->new({ RELATIVE => 1, ABSOLUTE => 1});

    eval {
        # Fill in the template, send template output to a text string
        $tt->process($templateName, \%templateVars, \$output );
    };

    if ($tt->error) {
        print STDERR "Error processing XML templatee: " . $tt->error . "\n";
        die "Exiting.\n";
    }

    $dsXML = $self->dbUtil->submitSQL($output, $verbose);

    eval {
        $doc = XML::LibXML->load_xml(string => $dsXML, { no_blanks => 1 });
    };

    if ($@) {
        print STDERR "Error submitting the project XML to the database: $@\n";
        die "Exiting.\n";
    }

    if ($@) {
        print STDERR "Error processing task XML: $@\n";
        print STDERR "The following is the invalid XML that was returned from Metabase: \n";
        print STDERR $output. "\n";
        die ": Processing halted because the generated XML document is not valid.\n";
    }

    # Return the XML document formatted with indentations.
    return $doc->toString(my $formatLevel=1);
}

# Make this Moose class immutable
__PACKAGE__->meta->make_immutable;

1;

__END__
