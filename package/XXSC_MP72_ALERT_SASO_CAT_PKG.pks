CREATE OR REPLACE PACKAGE APPS.XXSC_MP72_ALERT_SASO_CAT_PKG AUTHID DEFINER
AS
/***************************************************************************************************
 *                                                                                                 *
 *  PROJECT       MARAZZI - Oracle Applications                                                    *
 *                                                                                                 *
 *  DESCRIPTION   MP72 Programma di Alert SASO Category                                            *
 *                                                                                                 *
 *                                                                                                 *
 *  HISTORY:                                                                                       *
 *                                                                                                 *
 *  Version  Date         Author           Description                                             *
 *  -------  -----------  ---------------  ------------------------------------------------------  *
 *  1.0      27/03/2023   P.Interlandi    Creation - ERP-2469                                      *
 *                                                                                                 *
 ***************************************************************************************************/
                        
    PROCEDURE CREATE_TEMP (errbuf      OUT VARCHAR2
                    ,retcode     OUT VARCHAR2
                    ,p_msg IN VARCHAR2);

    FUNCTION BeforeReport RETURN BOOLEAN;
    FUNCTION AfterReport  RETURN BOOLEAN;       
END XXSC_MP72_ALERT_SASO_CAT_PKG;
/