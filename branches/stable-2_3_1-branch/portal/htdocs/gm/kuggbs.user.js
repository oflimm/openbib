// ==UserScript==
// @name          GBS mit KUG-Verfügbarkeit
// @namespace     http:/kug.ub.uni-koeln.de/gm/
// @description	  Verfügbarkeit im KUG in der Google Books Anzeige 'Über dieses Buch', basiert auf Skript von http://www.mundell.org
// @include       http://books.google.*/*
// ==/UserScript==

// Verwendung von DOM für Availability-Connector von OpenBib

(

function()
{
    var libraryUrl        = 'http://kug.ub.uni-koeln.de/portal/lastverteilung?view=kug';
    
    var libraryName = 'KUG';

    var libraryLookup = 
    {
        insertLink: function(isbn, hrefTitle, aLabel, color )
        {
            var div = origTitle.parentNode;
    	    var title = '';

            var newTitle = document.createElement('b');
            newTitle.setAttribute('class','sans');

            var titleText = document.createTextNode(title);
            newTitle.appendChild(titleText);
        
            var br = document.createElement('br');

            var link = document.createElement('a');
            link.setAttribute ('title', hrefTitle);

            if (isbn != 0){
               libraryUrl = libraryUrl+"&fs="+isbn;
            }

            link.setAttribute('href', libraryUrl);
            link.setAttribute('target', '_blank');
            link.setAttribute('style','font-size:small; font-weight:bold; color:' + color);

            var label = document.createTextNode( aLabel );

            link.appendChild(label);

            div.insertBefore(newTitle, origTitle);
            div.insertBefore(link, origTitle);
            div.insertBefore(br, origTitle);
        },

       insertSimilar: function(isbn, aSimilarTitles, aLabel, color )
        {                     
            var div = origTitle.parentNode;
    	    var title = '';

            var newTitle = document.createElement('b');
            newTitle.setAttribute('class','sans');

            var titleText = document.createTextNode(title);
            newTitle.appendChild(titleText);
        
            var br = document.createElement('br');

            var span1 = document.createElement('span');
            span1.setAttribute('style','font-size:small; font-weight:bold; color:' + color);
            
            var label = document.createTextNode( aLabel );

            span1.appendChild(label);

            var span2 = document.createElement('span');
            span2.setAttribute('style','font-size:small; font-weight:bold; color:' + color);

            var urlstring = " ( ";
            for (var i=0; i<aSimilarTitles.snapshotLength; i++) {
                var snapshot    = aSimilarTitles.snapshotItem(i);
                //GM_log(snapshot);
                var permalink   = snapshot.getElementsByTagName("permalink")[0].firstChild.nodeValue;
                var description = snapshot.getElementsByTagName("description")[0].firstChild.nodeValue;

                urlstring = urlstring+"<a href=\""+permalink+"\" title=\""+description+"\" target=\"_blank\">"+(i+1)+"</a> ";
            }
            urlstring = urlstring + ")";
            span2.innerHTML = urlstring;
            
            div.insertBefore(newTitle, origTitle);
            div.insertBefore(span1, origTitle);
            div.insertBefore(span2, origTitle);
            div.insertBefore(br, origTitle);
        },

        doLookup: function ( isbn )
        {
            GM_xmlhttpRequest
            ({
                method:'GET',
                url: 'http://kug.ub.uni-koeln.de/portal/connector/availability/' + isbn,
                onload:function(results)
                {
                    page = results.responseText;
                    var pagexml = (new DOMParser()).parseFromString(page, "text/xml");

                    var availability = pagexml.evaluate("//availability/size", pagexml, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null ).singleNodeValue.firstChild.nodeValue;
                    //GM_log('Availability:'+availability);

                    var similar_availability = pagexml.evaluate("//similar_record_availability/size", pagexml, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null ).singleNodeValue.firstChild.nodeValue;
                    //GM_log('Similar Availability:'+similar_availability);

                    //alert(page);
                    if ( availability > 0 )
                    {
                        libraryLookup.insertLink (
                            isbn,
                            "in mindestens einem Katalog vorhanden",
                            availability+" Titel im KUG vorhanden",
                            "green"
                        );
                    }
                    else if ( similar_availability > 0 )
                    {
                        var similar_titles = pagexml.evaluate("//similar_record_availability/catalogue", pagexml, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null );

                        libraryLookup.insertSimilar (
                            isbn,
                            similar_titles,
                            similar_availability+" Titel im KUG in anderen Ausgaben vorhanden ",
                            "orange"
                        );
                    }
                    else
                    {
                        libraryLookup.insertLink (
                            0,
                            "nicht im KUG vorhanden",
                            "Titel nicht im KUG vorhanden",
                            "red"
                        );
                    }
                }
            });
        }


    }

    //GM_log('running on GBS Skript');

    try { 
       var isbn = document.body.textContent.match(/ISBN (\d{7,9}[\d|X])/)[1];;        
    }
    catch (e) { 
       //GM_log('Fehler im isbn try');
       return; 
    }
    
    var origTitle = document.evaluate("//div[@class='titlewrap']", document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null ).singleNodeValue;

//    GM_log('Titel:'+origTitle.firstChild.nodeValue );
    if ( ! origTitle )
    { return; }

//     GM_log('ISBN:'+ isbn );

    libraryLookup.doLookup(isbn);

    }
)();
